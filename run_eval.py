#!/usr/bin/env python
import argparse
import json
import tempfile
from dataclasses import asdict, dataclass
from pathlib import Path

import docker
from datasets import load_dataset
from docker import errors as docker_errors

from sweagent.utils.log import get_logger

logger = get_logger("secb-eval", emoji="📊")

TAG = "v0.2"


@dataclass
class PatchResult:
    instance_id: str
    success: bool
    reason: str
    git_patch: str
    exit_code: int
    logs: str

    def to_dict(self):
        """Convert the dataclass instance to a dictionary."""
        return asdict(self)


def run_patch_evaluation(patch_input: str, dataset_dict: dict) -> list[PatchResult]:
    """Reads the preds.json file to extract `model_patch` and `instance_id`.

    Creates a container using the docker image formatted as:
      hwiwonlee/secb.x86_64.{instance_id}
    Within the container, it:
      1. Applies the patch to the project
      2. Compiles the project using `secb compile`
      3. Runs the PoC trigger command `secb run`
    If the `secb run` command returns a 0 exit code, the patch is deemed successful.
    """
    # Parse the JSON file (not JSONL)
    with open(patch_input) as f:
        patch_data = json.load(f)

    if not patch_data:
        msg = f"No valid JSON found in {patch_input}"
        raise ValueError(msg)

    results: list[PatchResult] = []
    for instance_id, pd in patch_data.items():
        if not instance_id:
            msg = "instance_id not found in the JSON data"
            raise ValueError(msg)

        # Extract working directory from the instance_id
        work_dir = dataset_dict[instance_id]["work_dir"]
        logger.debug(f"Work directory: {work_dir}")

        # Expecting git_patch to be inside the "test_result" dictionary as per provided sample.
        model_patch = pd.get("model_patch")
        if not model_patch:
            msg = "The model failed to submit a patch. Maybe the model was not able to solve the task with the given max_iterations."
            results.append(
                PatchResult(
                    instance_id=instance_id,
                    success=False,
                    reason=msg,
                    git_patch="",
                    exit_code=1,
                    logs="",
                )
            )
            continue

        # Replace all "\r\n" with "\n" in the model_patch.
        if model_patch is not None:
            model_patch = model_patch.replace("\r\n", "\n")

        # Construct the docker image name as specified.
        docker_image = f"hwiwonlee/secb.x86_64.{instance_id}:{TAG}"
        logger.info(f"Using docker image: {docker_image} for instance {instance_id}")

        # Create a temporary directory to hold the patch file.
        with tempfile.TemporaryDirectory() as tmp_dir:
            patch_file_path = Path(tmp_dir) / "patch.diff"
            # Remove any trailing "%" characters from model_patch before writing to file.
            with patch_file_path.open("w") as pf:
                pf.write(model_patch + "\n")
            logger.info(f"Patch file written to: {patch_file_path}")

            client = docker.from_env()  # type: ignore

            # Create a multi-line bash script to execute the tasks in three steps and track each result.
            script = """
echo "Step 1: Git apply"
git apply --verbose --reject /patch/patch.diff
ret=$?
if [ ${ret} -ne 0 ]; then
    echo "FAIL_STEP: Git apply; exit code=${ret}"
    exit ${ret}
else
    echo "SUCCESS: Git apply passed; exit code=${ret}"
fi

echo "Step 2: Compile"
secb compile
ret=$?
if [ ${ret} -ne 0 ]; then
    echo "FAIL_STEP: Compile; exit code=${ret}"
    exit ${ret}
else
    echo "SUCCESS: Compile passed; exit code=${ret}"
fi

echo "Step 3: Run PoC"
secb run
ret=$?
if [ ${ret} -ne 0 ]; then
    echo "FAIL_STEP: Run PoC; exit code=${ret}"
    exit ${ret}
else
    echo "SUCCESS: Run PoC passed; exit code=${ret}"
    exit 0
fi
    """
            logger.info(f"Running docker container with image: {docker_image} using multi-step script")

            try:
                container = client.containers.create(
                    image=docker_image,
                    command=["bash", "-c", script],
                    working_dir=work_dir,
                    security_opt=["seccomp=unconfined"],
                    volumes={tmp_dir: {"bind": "/patch", "mode": "rw"}},
                )
            except docker_errors.ImageNotFound:
                logger.info(f"Image {docker_image} not found locally. Attempting to pull...")
                try:
                    client.images.pull(docker_image)
                    logger.info(f"Successfully pulled image: {docker_image}")
                    # Retry container creation after pulling the image
                    container = client.containers.create(
                        image=docker_image,
                        command=["bash", "-c", script],
                        working_dir=work_dir,
                        security_opt=["seccomp=unconfined"],
                        volumes={tmp_dir: {"bind": "/patch", "mode": "rw"}},
                    )
                except Exception as e:
                    error_msg = f"Failed to pull image {docker_image}: {str(e)}"
                    logger.error(error_msg)
                    results.append(
                        PatchResult(
                            instance_id=instance_id,
                            success=False,
                            reason=error_msg,
                            git_patch=model_patch,
                            exit_code=1,
                            logs=error_msg,
                        )
                    )
                    continue
            except Exception as e:
                error_msg = f"Failed to create container with image {docker_image}: {str(e)}"
                logger.error(error_msg)
                results.append(
                    PatchResult(
                        instance_id=instance_id,
                        success=False,
                        reason=error_msg,
                        git_patch=model_patch,
                        exit_code=1,
                        logs=error_msg,
                    )
                )
                continue

            container.start()
            exit_result = container.wait()
            logs = container.logs()
            container.remove()

            decoded_logs = logs.decode("utf-8")
            logger.info(f"Docker container logs: {decoded_logs}")

            if exit_result["StatusCode"] == 0:
                step_reason = "Patch applied, compiled, and run successfully (secb run returned 0)."
                logger.info(step_reason)
                print("Patch was successful: secb run returned 0")
            else:
                # Parse logs to find which step failed.
                step_reason = "Patch evaluation failed."
                for line in decoded_logs.splitlines():
                    if line.startswith("FAIL_STEP:"):
                        step_reason = line.strip()
                        break
                logger.error(f"Patch evaluation failed: {step_reason}")
                print(f"Patch failed: {step_reason}")

            results.append(
                PatchResult(
                    instance_id=instance_id,
                    success=exit_result["StatusCode"] == 0,
                    reason=step_reason,
                    git_patch=model_patch,
                    exit_code=exit_result["StatusCode"],
                    logs=decoded_logs,
                )
            )

    return results


def main():
    parser = argparse.ArgumentParser(description="BenchDyne Evaluation Runner for patch application and testing.")
    parser.add_argument(
        "--input-file",
        required=True,
        help="Path to the output.jsonl file containing git_patch and instance_id for patch evaluation",
    )
    args = parser.parse_args()
    parser.add_argument(
        "--dataset",
        default="hwiwonl/SEC-bench",
        help="Hugging Face dataset name to load",
    )
    parser.add_argument(
        "--split",
        default="eval",
        help="Dataset split to use",
    )
    args = parser.parse_args()

    # Load the dataset from Hugging Face
    try:
        logger.info(f"Loading dataset {args.dataset} with split {args.split}")
        dataset = load_dataset(args.dataset, split=args.split)

        # Convert dataset to dictionary format
        dataset_dict = {item["instance_id"]: item for item in dataset}
        logger.info(f"Loaded {len(dataset_dict)} instances from {args.dataset}")
    except Exception as e:
        logger.error(f"Failed to load dataset {args.dataset}: {e}")
        dataset_dict = {}

    # Convert the provided input file path to a Path object
    input_path = Path(args.input_file)

    try:
        # You can pass input_path directly since open() accepts Path objects.
        outputs = run_patch_evaluation(str(input_path), dataset_dict)
        # Replace os.path.join() with the "/" operator provided by pathlib.
        report_path = input_path.parent / "report.jsonl"
        with report_path.open("w") as report_file:
            for output in outputs:
                report_file.write(json.dumps(output.to_dict()) + "\n")
    except Exception as e:
        logger.exception("Error during patch evaluation")
        print(f"Error: {e}")
        exit(1)


if __name__ == "__main__":
    main()
