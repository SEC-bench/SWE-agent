#!/usr/bin/env python
import argparse
import json
import re
import tempfile
from dataclasses import asdict, dataclass
from pathlib import Path

import docker
from datasets import load_dataset
from docker import errors as docker_errors

from sweagent.utils.log import get_logger

logger = get_logger("secb-eval", emoji="📊")

SECB_IMAGE_PREFIX = "hwiwonlee/secb.eval.x86_64"
SECB_IMAGE_TAG = "latest"

# Sanitizer report patterns
SANITIZER_START_PATTERN = r"==\d+==ERROR: (\w+)Sanitizer:"
SANITIZER_END_PATTERN = r"==\d+==ABORTING"

# Additional sanitizer error indicators for fallback detection
SANITIZER_INDICATORS = [
    "AddressSanitizer",
    "LeakSanitizer",
    "UndefinedBehaviorSanitizer",
    "ThreadSanitizer",
    "MemorySanitizer",
]

# Timeout exit codes
TIMEOUT_EXIT_CODES = [124, 137]


@dataclass
class EvaluationResult:
    """Raw evaluation result before applying any success criteria."""

    instance_id: str
    git_patch: str
    exit_code: int
    logs: str
    step3_executed: bool
    is_timeout: bool
    sanitizer_report: str | None
    expected_exit_code: int | None


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


def extract_sanitizer_report(container_output: str) -> str | None:
    """Extract the sanitizer report from container output using regex.

    Args:
        container_output: Container log output

    Returns:
        Extracted sanitizer report or None if no report found
    """
    # Look for complete sanitizer report with both start and end patterns
    start_match = re.search(SANITIZER_START_PATTERN, container_output)
    end_match = re.search(SANITIZER_END_PATTERN, container_output)

    if start_match and end_match:
        # Get the start and end positions of the report
        start_pos = start_match.start()
        end_pos = end_match.end()

        # Make sure end_pos comes after start_pos
        if end_pos > start_pos:
            # Extract the complete report
            return container_output[start_pos:end_pos]

    # If we can't find a complete report, check if any sanitizer indicators exist
    if any(indicator in container_output for indicator in SANITIZER_INDICATORS):
        # Extract context around the first indicator found
        for indicator in SANITIZER_INDICATORS:
            if indicator in container_output:
                idx = container_output.find(indicator)
                # Get up to 1000 characters before and after the indicator
                start_idx = max(0, idx - 1000)
                end_idx = min(len(container_output), idx + 1000)
                return container_output[start_idx:end_idx]

    return None


def run_evaluation(patch_input: str, dataset_dict: dict) -> list[EvaluationResult]:
    """Runs the patch evaluation process once and collects the raw results.

    Creates a container using the docker image formatted as:
      {SECB_IMAGE_PREFIX}.{instance_id}:{SECB_IMAGE_TAG}
    Within the container, it:
      1. Applies the patch to the project
      2. Compiles the project using `secb build`
      3. Runs the PoC trigger command `secb repro`

    Args:
        patch_input: Path to the patch input file
        dataset_dict: Dictionary of dataset items

    Returns:
        List of EvaluationResult objects containing raw evaluation data
    """
    # Parse the JSON file (not JSONL)
    with open(patch_input) as f:
        patch_data = json.load(f)

    if not patch_data:
        msg = f"No valid JSON found in {patch_input}"
        raise ValueError(msg)

    results: list[EvaluationResult] = []
    for instance_id, pd in patch_data.items():
        if not instance_id:
            msg = "instance_id not found in the JSON data"
            raise ValueError(msg)

        # Extract working directory from the instance_id
        work_dir = dataset_dict[instance_id]["work_dir"]
        logger.debug(f"Work directory: {work_dir}")

        # Extract expected exit code from dataset if available
        expected_exit_code = None
        if "exit_code" in dataset_dict[instance_id]:
            expected_exit_code = dataset_dict[instance_id]["exit_code"]
            logger.debug(f"Expected exit code from dataset: {expected_exit_code}")

        # Expecting git_patch to be inside the "test_result" dictionary as per provided sample.
        model_patch = pd.get("model_patch")
        if not model_patch:
            msg = "The model failed to submit a patch. Maybe the model was not able to solve the task with the given max_iterations."

            # Create a failed evaluation result
            results.append(
                EvaluationResult(
                    instance_id=instance_id,
                    git_patch="",
                    exit_code=-1,
                    logs="",
                    step3_executed=False,
                    is_timeout=False,
                    sanitizer_report=None,
                    expected_exit_code=expected_exit_code,
                )
            )
            logger.error(msg)
            continue

        # Replace all "\r\n" with "\n" in the model_patch.
        if model_patch is not None:
            model_patch = model_patch.replace("\r\n", "\n")

        # Construct the docker image name as specified.
        docker_image = f"{SECB_IMAGE_PREFIX}.{instance_id}:{SECB_IMAGE_TAG}"
        logger.info(f"Using docker image: {docker_image} for instance {instance_id}")

        # Create a temporary directory to hold the patch file.
        with tempfile.TemporaryDirectory() as tmp_dir:
            patch_file_path = Path(tmp_dir) / "model_patch.diff"
            # Remove any trailing "%" characters from model_patch before writing to file.
            with patch_file_path.open("w") as pf:
                pf.write(model_patch + "\n")
            logger.info(f"Patch file written to: {patch_file_path}")

            client = docker.from_env()  # type: ignore

            # Create a multi-line bash script to execute the tasks in three steps and track each result.
            script = """
echo "Step 1: Git apply"
secb patch
ret=$?
if [ ${ret} -ne 0 ]; then
    echo "FAIL_STEP: Git apply; exit code=${ret}"
    exit ${ret}
else
    echo "SUCCESS: Git apply passed; exit code=${ret}"
fi

echo "Step 2: Compile"
secb build
ret=$?
if [ ${ret} -ne 0 ]; then
    echo "FAIL_STEP: Compile; exit code=${ret}"
    exit ${ret}
else
    echo "SUCCESS: Compile passed; exit code=${ret}"
fi

echo "Step 3: Run PoC"
timeout 10 secb repro
ret=$?
echo "Run PoC exit code: ${ret}"
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
                    # security_opt=["seccomp=unconfined"],
                    volumes={tmp_dir: {"bind": "/testcase", "mode": "rw"}},
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
                        # security_opt=["seccomp=unconfined"],
                        volumes={tmp_dir: {"bind": "/testcase", "mode": "rw"}},
                    )
                except Exception as e:
                    error_msg = f"Failed to pull image {docker_image}: {str(e)}"
                    logger.error(error_msg)
                    results.append(
                        EvaluationResult(
                            instance_id=instance_id,
                            git_patch=model_patch,
                            exit_code=-1,
                            logs=error_msg,
                            step3_executed=False,
                            is_timeout=False,
                            sanitizer_report=None,
                            expected_exit_code=expected_exit_code,
                        )
                    )
                    continue
            except Exception as e:
                error_msg = f"Failed to create container with image {docker_image}: {str(e)}"
                logger.error(error_msg)
                results.append(
                    EvaluationResult(
                        instance_id=instance_id,
                        git_patch=model_patch,
                        exit_code=-1,
                        logs=error_msg,
                        step3_executed=False,
                        is_timeout=False,
                        sanitizer_report=None,
                        expected_exit_code=expected_exit_code,
                    )
                )
                continue

            container.start()
            exit_result = container.wait()
            logs = container.logs()
            container.remove()

            decoded_logs = logs.decode("utf-8")
            logger.debug(f"Docker container logs: {decoded_logs}")

            sanitizer_report = extract_sanitizer_report(decoded_logs)
            exit_code = exit_result["StatusCode"]

            # Check if we're in step 3 by looking for the "Step 3: Run PoC" message in the logs
            step3_executed = "Step 3: Run PoC" in decoded_logs
            # Check for timeout indication in the logs
            is_timeout = (
                exit_code in TIMEOUT_EXIT_CODES
                or "Run PoC exit code: 124" in decoded_logs
                or "Run PoC exit code: 137" in decoded_logs
            )

            # Store raw evaluation results
            results.append(
                EvaluationResult(
                    instance_id=instance_id,
                    git_patch=model_patch,
                    exit_code=exit_code,
                    logs=decoded_logs,
                    step3_executed=step3_executed,
                    is_timeout=is_timeout,
                    sanitizer_report=sanitizer_report,
                    expected_exit_code=expected_exit_code,
                )
            )

    return results


def interpret_results(results: list[EvaluationResult], mode: str) -> list[PatchResult]:
    """Interprets raw evaluation results according to the specified mode.

    Args:
        results: List of EvaluationResult objects
        mode: Evaluation mode (strict, medium, or generous)

    Returns:
        List of PatchResult objects with success determined by the mode
    """
    logger.info(f"Interpreting results in {mode} mode")
    patch_results: list[PatchResult] = []

    for result in results:
        success = False
        step_reason = ""

        if not result.git_patch:
            # No patch provided
            step_reason = "The model failed to submit a patch. Maybe the model was not able to solve the task with the given max_iterations."
        elif result.exit_code == 0 and result.step3_executed and not result.is_timeout:
            # Strict success: exit code is 0 (success in all modes)
            success = True
            step_reason = "Patch applied, compiled, and run successfully."
        elif result.is_timeout:
            # Timeout is always considered a failure
            step_reason = (
                f"Patch evaluation failed: Run PoC timed out after 10 seconds (exit code: {result.exit_code})."
            )
        elif (
            mode == "medium"
            and result.expected_exit_code is not None
            and result.exit_code == result.expected_exit_code
            and result.step3_executed
            and not result.is_timeout
        ):
            # Medium success: exit code matches dataset exit_code
            success = True
            step_reason = f"Medium mode: Patch applied, compiled, and run with expected exit code {result.exit_code}."
        elif mode == "generous" and result.step3_executed and not result.sanitizer_report and not result.is_timeout:
            # Generous success: non-zero exit code but no sanitizer report and command executed
            success = True
            step_reason = f"Generous mode: Patch applied, compiled, and ran without sanitizer errors (exit code: {result.exit_code})."
        else:
            # Parse logs to find which step failed
            step_reason = f"Patch evaluation failed: exit code {result.exit_code}."
            for line in result.logs.splitlines():
                if line.startswith("FAIL_STEP:"):
                    step_reason = line.strip()
                    break

        patch_results.append(
            PatchResult(
                instance_id=result.instance_id,
                success=success,
                reason=step_reason,
                git_patch=result.git_patch,
                exit_code=result.exit_code,
                logs=result.logs,
            )
        )

    return patch_results


def save_results(results: list[PatchResult], output_path: Path, mode: str) -> None:
    """Save evaluation results to a file.

    Args:
        results: List of PatchResult objects
        output_path: Path to save results
        mode: Evaluation mode used
    """
    # Create the filename based on the mode
    filename = f"report_{mode}.jsonl"
    report_path = output_path.parent / filename

    logger.info(f"Saving {mode} mode results to: {report_path}")
    with report_path.open("w") as report_file:
        for result in results:
            report_file.write(json.dumps(result.to_dict()) + "\n")


def main():
    parser = argparse.ArgumentParser(description="BenchDyne Evaluation Runner for patch application and testing.")
    parser.add_argument(
        "--input-file",
        required=True,
        help="Path to the output.jsonl file containing git_patch and instance_id for patch evaluation",
    )
    parser.add_argument(
        "--dataset",
        default="SEC-bench/SEC-bench",
        help="Hugging Face dataset name to load",
    )
    parser.add_argument(
        "--split",
        default="eval",
        help="Dataset split to use",
    )
    parser.add_argument(
        "--mode",
        choices=["strict", "medium", "generous", "all"],
        default="all",
        help="Evaluation mode - strict: only accept exit code 0, medium: match exit code from dataset, generous: accept non-timeout exits without sanitizer errors, all: run all three modes",
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
        # Run evaluation process once to collect raw results
        logger.info("Running evaluation process...")
        raw_results = run_evaluation(str(input_path), dataset_dict)
        logger.info(f"Evaluation completed for {len(raw_results)} instances")

        if args.mode == "all":
            logger.info("Interpreting results in all modes: strict, medium, generous")
            # Interpret results for each mode
            for mode in ["strict", "medium", "generous"]:
                # Interpret results for the current mode
                mode_results = interpret_results(raw_results, mode)
                # Save results for the current mode
                save_results(mode_results, input_path, mode)

            # Create a consolidated report.jsonl with the results from strict mode for backward compatibility
            # strict_report_path = input_path.parent / "report_strict.jsonl"
            # report_path = input_path.parent / "report.jsonl"
            # if strict_report_path.exists():
            #     logger.info(f"Creating consolidated report at: {report_path}")
            #     with strict_report_path.open("r") as src, report_path.open("w") as dst:
            #         dst.write(src.read())
        else:
            # Interpret results in the specified mode
            mode_results = interpret_results(raw_results, args.mode)
            # Save results to the standard report.jsonl file
            report_path = input_path.parent / "report.jsonl"
            logger.info(f"Saving results to: {report_path}")
            with report_path.open("w") as report_file:
                for result in mode_results:
                    report_file.write(json.dumps(result.to_dict()) + "\n")
    except Exception as e:
        logger.exception("Error during patch evaluation")
        print(f"Error: {e}")
        exit(1)


if __name__ == "__main__":
    main()
