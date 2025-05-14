#!/bin/bash

# Create logs directory if it doesn't exist
LOGS_DIR="./logs"
mkdir -p "$LOGS_DIR"

# Function to run a command and log both stdout and stderr
run_with_logging() {
    local log_name="$1"
    shift  # Remove the first argument (log name) and shift remaining args
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local log_file="$LOGS_DIR/${timestamp}_${log_name}.log"

    echo -e "${BLUE}${BOLD}Running $log_name - Logging to $log_file${RESET}"

    # Use tee to capture both stdout and stderr to the log file
    { "$@" 2>&1 1>&3 3>&- | tee -a "$log_file" >&2; } 3>&1 1>&2 | tee -a "$log_file"

    echo -e "${GREEN}${BOLD}Completed $log_name - Log saved to $log_file${RESET}"
    echo -e "${BOLD}----------------------------------------${RESET}"
}


# Check if mode argument is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <mode>"
    echo "Mode can be 'infer' or 'eval' or 'view'"
    exit 1
fi

mode="$1"

clear

# Validate mode argument
if [ "$mode" != "infer" ] && [ "$mode" != "eval" ] && [ "$mode" != "view" ]; then
    echo "Error: Mode must be either 'infer' or 'eval' or 'view'"
    exit 1
fi

if [ "$mode" == "infer" ]; then
    ## Ablation Study for the helper script
    # ./run_infer.sh -m sonnet -f ./config/secbench_no_helper.yaml -c 1.5 -t 0.0 -s eval -l :30 -n 75 -w 2

    ## Data contamination
    # ./run_infer.sh -m haiku -t secb_patch -f ./config/secb_patch.yaml -c 1.0 -t 0.0 -s after -l :15 -n 75 -w 2
    # ./run_infer.sh -m haiku -t secb_patch -f ./config/secb_patch.yaml -c 1.0 -t 0.0 -s before -l :15 -n 75 -w 2
    # ./run_infer.sh -m 4o -t secb_patch -f ./config/secb_patch.yaml -c 1.0 -t 0.0 -s after -l :15 -n 75 -w 1
    # ./run_infer.sh -m 4o -t secb_patch -f ./config/secb_patch.yaml -c 1.0 -t 0.0 -s before -l :15 -n 75 -w 1

    # ./run_infer.sh -m haiku -t secb_poc -f ./config/secb_poc.yaml -c 1.0 -e 0.0 -s after -l :15 -n 75 -w 2
    # ./run_infer.sh -m haiku -t secb_poc -f ./config/secb_poc.yaml -c 1.0 -e 0.0 -s before -l :15 -n 75 -w 2
    # ./run_infer.sh -m 4o -t secb_poc -f ./config/secb_poc.yaml -c 1.0 -e 0.0 -s after -l :15 -n 75 -w 1
    # ./run_infer.sh -m 4o -t secb_poc -f ./config/secb_poc.yaml -c 1.0 -e 0.0 -s before -l :15 -n 75 -w 1

    ## PoC generation
    # run_with_logging "sonnet-poc" ./run_infer.sh -m sonnet -t secb_poc -f ./config/secb_poc.yaml -c 1.5 -e 0.0 -s eval -l :200 -n 75 -w 2
    ./run_infer.sh -m 4o -t secb_poc -f ./config/secb_poc.yaml -c 1.0 -e 0.0 -s eval -l 80:82 -n 75 -w 2
    ./run_infer.sh -m o3 -t secb_poc -f ./config/secb_poc.yaml -c 1.0 -e 0.0 -s eval -l 80:82 -n 75 -w 2

    ## Patch generation
    # run_with_logging "sonnet-patch" ./run_infer.sh -m sonnet -t secb_patch -f ./config/secb_patch.yaml -c 1.5 -e 0.0 -s eval -l :200 -n 75 -w 2
    ./run_infer.sh -m 4o -t secb_patch -f ./config/secb_patch.yaml -c 1.0 -e 0.0 -s eval -l 80:82 -n 75 -w 2
    ./run_infer.sh -m o3 -t secb_patch -f ./config/secb_patch.yaml -c 1.0 -e 0.0 -s eval -l 80:82 -n 75 -w 2

    ## Deprecated commands
    # ./run_infer.sh -m 4o -f ./config/secbench.yaml -c 1.0 -t 0.0 -s eval -l :80 -n 75 -w 2
    # ./run_infer.sh -m o3 -f ./config/secbench.yaml -c 1.0 -t 0.0 -s eval -l :80 -n 75 -w 2
    # ./run_infer.sh -m gemini-pro -f ./config/secbench.yaml -c 1.5 -t 0.0 -s eval -l :80 -n 75 -w 1
elif [ "$mode" == "eval" ]; then
    # Get the user ID
    id=$(whoami)
    python run_eval.py --input-file trajectories/${id}/secbench__anthropic/claude-3-7-sonnet-20250219__t-0.00__p-0.95__c-1.50___secbench_eval/preds.json --mode all --num-workers 8
    python run_eval.py --input-file trajectories/${id}/secbench__gpt-4o__t-0.00__p-0.95__c-1.00___secbench_eval/preds.json --mode all --num-workers 8
    python run_eval.py --input-file trajectories/${id}/secbench__o3-mini__t-0.00__p-0.95__c-1.00___secbench_eval/preds.json --mode all --num-workers 8
    # python run_eval.py --input-file trajectories/${id}/secbench__openai/gemini-2.5-pro-preview-03-25__t-0.00__p-0.95__c-1.00___secbench_eval/preds.json --mode all
elif [ "$mode" == "view" ]; then
    # Get the user ID
    id=$(whoami)

    echo -e "\e[1;36mClaude 3.7 Sonnet 20250219\e[0m"
    jq -r '[.instance_id, .success, .reason] | @tsv' trajectories/${id}/secbench__anthropic/claude-3-7-sonnet-20250219__t-0.00__p-0.95__c-1.50___secbench_eval/report.jsonl
    echo -e "--- Statistics ---"

    # Calculate total entries
    TOTAL_CLAUDE=$(jq -r '.reason' trajectories/${id}/secbench__anthropic/claude-3-7-sonnet-20250219__t-0.00__p-0.95__c-1.50___secbench_eval/report.jsonl | wc -l)

    # Calculate counts
    SUCCESS_CLAUDE=$(jq -r 'select(.reason | contains("Patch applied, compiled, and run successfully.")) | .reason' trajectories/${id}/secbench__anthropic/claude-3-7-sonnet-20250219__t-0.00__p-0.95__c-1.50___secbench_eval/report.jsonl | wc -l)
    NO_PATCH_CLAUDE=$(jq -r 'select(.reason | contains("The model failed to submit a patch.")) | .reason' trajectories/${id}/secbench__anthropic/claude-3-7-sonnet-20250219__t-0.00__p-0.95__c-1.50___secbench_eval/report.jsonl | wc -l)
    GIT_CLAUDE=$(jq -r 'select(.reason | contains("FAIL_STEP: Git apply")) | .reason' trajectories/${id}/secbench__anthropic/claude-3-7-sonnet-20250219__t-0.00__p-0.95__c-1.50___secbench_eval/report.jsonl | wc -l)
    COMPILE_CLAUDE=$(jq -r 'select(.reason | contains("FAIL_STEP: Compile")) | .reason' trajectories/${id}/secbench__anthropic/claude-3-7-sonnet-20250219__t-0.00__p-0.95__c-1.50___secbench_eval/report.jsonl | wc -l)
    FAIL_FIX_CLAUDE=$(jq -r 'select(.reason | contains("FAIL_STEP: Run PoC")) | .reason' trajectories/${id}/secbench__anthropic/claude-3-7-sonnet-20250219__t-0.00__p-0.95__c-1.50___secbench_eval/report.jsonl | wc -l)

    # Calculate percentages
    SUCCESS_PERC_CLAUDE=$(echo "scale=2; $SUCCESS_CLAUDE * 100 / $TOTAL_CLAUDE" | bc)
    NO_PATCH_PERC_CLAUDE=$(echo "scale=2; $NO_PATCH_CLAUDE * 100 / $TOTAL_CLAUDE" | bc)
    GIT_PERC_CLAUDE=$(echo "scale=2; $GIT_CLAUDE * 100 / $TOTAL_CLAUDE" | bc)
    COMPILE_PERC_CLAUDE=$(echo "scale=2; $COMPILE_CLAUDE * 100 / $TOTAL_CLAUDE" | bc)
    FAIL_FIX_PERC_CLAUDE=$(echo "scale=2; $FAIL_FIX_CLAUDE * 100 / $TOTAL_CLAUDE" | bc)

    # Display results
    echo -e "\e[1;32mSuccess: $SUCCESS_CLAUDE/$TOTAL_CLAUDE ($SUCCESS_PERC_CLAUDE%)\e[0m"
    echo "No Patch: $NO_PATCH_CLAUDE/$TOTAL_CLAUDE ($NO_PATCH_PERC_CLAUDE%)"
    echo "Patch Format Error: $GIT_CLAUDE/$TOTAL_CLAUDE ($GIT_PERC_CLAUDE%)"
    echo "Compile Error: $COMPILE_CLAUDE/$TOTAL_CLAUDE ($COMPILE_PERC_CLAUDE%)"
    echo "Fail to Fix: $FAIL_FIX_CLAUDE/$TOTAL_CLAUDE ($FAIL_FIX_PERC_CLAUDE%)"

    echo -e "\n\e[1;36mGPT 4o\e[0m"
    jq -r '[.instance_id, .success, .reason] | @tsv' trajectories/${id}/secbench__gpt-4o__t-0.00__p-0.95__c-1.00___secbench_eval/report.jsonl
    echo -e "--- Statistics ---"

    # Calculate total entries
    TOTAL_GPT=$(jq -r '.reason' trajectories/${id}/secbench__gpt-4o__t-0.00__p-0.95__c-1.00___secbench_eval/report.jsonl | wc -l)

    # Calculate counts
    SUCCESS_GPT=$(jq -r 'select(.reason | contains("Patch applied, compiled, and run successfully.")) | .reason' trajectories/${id}/secbench__gpt-4o__t-0.00__p-0.95__c-1.00___secbench_eval/report.jsonl | wc -l)
    NO_PATCH_GPT=$(jq -r 'select(.reason | contains("The model failed to submit a patch.")) | .reason' trajectories/${id}/secbench__gpt-4o__t-0.00__p-0.95__c-1.00___secbench_eval/report.jsonl | wc -l)
    GIT_GPT=$(jq -r 'select(.reason | contains("FAIL_STEP: Git apply")) | .reason' trajectories/${id}/secbench__gpt-4o__t-0.00__p-0.95__c-1.00___secbench_eval/report.jsonl | wc -l)
    COMPILE_GPT=$(jq -r 'select(.reason | contains("FAIL_STEP: Compile")) | .reason' trajectories/${id}/secbench__gpt-4o__t-0.00__p-0.95__c-1.00___secbench_eval/report.jsonl | wc -l)
    FAIL_FIX_GPT=$(jq -r 'select(.reason | contains("FAIL_STEP: Run PoC")) | .reason' trajectories/${id}/secbench__gpt-4o__t-0.00__p-0.95__c-1.00___secbench_eval/report.jsonl | wc -l)

    # Calculate percentages
    SUCCESS_PERC_GPT=$(echo "scale=2; $SUCCESS_GPT * 100 / $TOTAL_GPT" | bc)
    NO_PATCH_PERC_GPT=$(echo "scale=2; $NO_PATCH_GPT * 100 / $TOTAL_GPT" | bc)
    GIT_PERC_GPT=$(echo "scale=2; $GIT_GPT * 100 / $TOTAL_GPT" | bc)
    COMPILE_PERC_GPT=$(echo "scale=2; $COMPILE_GPT * 100 / $TOTAL_GPT" | bc)
    FAIL_FIX_PERC_GPT=$(echo "scale=2; $FAIL_FIX_GPT * 100 / $TOTAL_GPT" | bc)

    # Display results
    echo -e "\e[1;32mSuccess: $SUCCESS_GPT/$TOTAL_GPT ($SUCCESS_PERC_GPT%)\e[0m"
    echo "No Patch: $NO_PATCH_GPT/$TOTAL_GPT ($NO_PATCH_PERC_GPT%)"
    echo "Patch Format Error: $GIT_GPT/$TOTAL_GPT ($GIT_PERC_GPT%)"
    echo "Compile Error: $COMPILE_GPT/$TOTAL_GPT ($COMPILE_PERC_GPT%)"
    echo "Fail to Fix: $FAIL_FIX_GPT/$TOTAL_GPT ($FAIL_FIX_PERC_GPT%)"

    echo -e "\n\e[1;36mGemini 2.5 Pro\e[0m"
    jq -r '[.instance_id, .success, .reason] | @tsv' trajectories/${id}/secbench__openai/gemini-2.5-pro-preview-03-25__t-0.00__p-0.95__c-1.00___secbench_eval/report.jsonl
    echo -e "--- Statistics ---"

    # Calculate total entries
    TOTAL_GEMINI=$(jq -r '.reason' trajectories/${id}/secbench__openai/gemini-2.5-pro-preview-03-25__t-0.00__p-0.95__c-1.00___secbench_eval/report.jsonl | wc -l)

    # Calculate counts
    SUCCESS_GEMINI=$(jq -r 'select(.reason | contains("Patch applied, compiled, and run successfully.")) | .reason' trajectories/${id}/secbench__openai/gemini-1.5-pro__t-0.00__p-0.95__c-1.00___secbench_eval/report.jsonl | wc -l)
    NO_PATCH_GEMINI=$(jq -r 'select(.reason | contains("The model failed to submit a patch.")) | .reason' trajectories/${id}/secbench__openai/gemini-1.5-pro__t-0.00__p-0.95__c-1.00___secbench_eval/report.jsonl | wc -l)
    GIT_GEMINI=$(jq -r 'select(.reason | contains("FAIL_STEP: Git apply")) | .reason' trajectories/${id}/secbench__openai/gemini-1.5-pro__t-0.00__p-0.95__c-1.00___secbench_eval/report.jsonl | wc -l)
    COMPILE_GEMINI=$(jq -r 'select(.reason | contains("FAIL_STEP: Compile")) | .reason' trajectories/${id}/secbench__openai/gemini-1.5-pro__t-0.00__p-0.95__c-1.00___secbench_eval/report.jsonl | wc -l)
    FAIL_FIX_GEMINI=$(jq -r 'select(.reason | contains("FAIL_STEP: Run PoC")) | .reason' trajectories/${id}/secbench__openai/gemini-1.5-pro__t-0.00__p-0.95__c-1.00___secbench_eval/report.jsonl | wc -l)

    # Calculate percentages
    SUCCESS_PERC_GEMINI=$(echo "scale=2; $SUCCESS_GEMINI * 100 / $TOTAL_GEMINI" | bc)
    NO_PATCH_PERC_GEMINI=$(echo "scale=2; $NO_PATCH_GEMINI * 100 / $TOTAL_GEMINI" | bc)
    GIT_PERC_GEMINI=$(echo "scale=2; $GIT_GEMINI * 100 / $TOTAL_GEMINI" | bc)
    COMPILE_PERC_GEMINI=$(echo "scale=2; $COMPILE_GEMINI * 100 / $TOTAL_GEMINI" | bc)
    FAIL_FIX_PERC_GEMINI=$(echo "scale=2; $FAIL_FIX_GEMINI * 100 / $TOTAL_GEMINI" | bc)

    # Display results
    echo -e "\e[1;32mSuccess: $SUCCESS_GEMINI/$TOTAL_GEMINI ($SUCCESS_PERC_GEMINI%)\e[0m"
    echo "No Patch: $NO_PATCH_GEMINI/$TOTAL_GEMINI ($NO_PATCH_PERC_GEMINI%)"
    echo "Patch Format Error: $GIT_GEMINI/$TOTAL_GEMINI ($GIT_PERC_GEMINI%)"
    echo "Compile Error: $COMPILE_GEMINI/$TOTAL_GEMINI ($COMPILE_PERC_GEMINI%)"
    echo "Fail to Fix: $FAIL_FIX_GEMINI/$TOTAL_GEMINI ($FAIL_FIX_PERC_GEMINI%)"


    echo -e "\n\e[1;36mO3 Mini\e[0m"
    jq -r '[.instance_id, .success, .reason] | @tsv' trajectories/${id}/secbench__o3-mini__t-0.00__p-0.95__c-1.00___secbench_eval/report.jsonl
    echo -e "--- Statistics ---"

    # Calculate total entries
    TOTAL_O3=$(jq -r '.reason' trajectories/${id}/secbench__o3-mini__t-0.00__p-0.95__c-1.00___secbench_eval/report.jsonl | wc -l)

    # Calculate counts
    SUCCESS_O3=$(jq -r 'select(.reason | contains("Patch applied, compiled, and run successfully.")) | .reason' trajectories/${id}/secbench__o3-mini__t-0.00__p-0.95__c-1.00___secbench_eval/report.jsonl | wc -l)
    NO_PATCH_O3=$(jq -r 'select(.reason | contains("The model failed to submit a patch.")) | .reason' trajectories/${id}/secbench__o3-mini__t-0.00__p-0.95__c-1.00___secbench_eval/report.jsonl | wc -l)
    GIT_O3=$(jq -r 'select(.reason | contains("FAIL_STEP: Git apply")) | .reason' trajectories/${id}/secbench__o3-mini__t-0.00__p-0.95__c-1.00___secbench_eval/report.jsonl | wc -l)
    COMPILE_O3=$(jq -r 'select(.reason | contains("FAIL_STEP: Compile")) | .reason' trajectories/${id}/secbench__o3-mini__t-0.00__p-0.95__c-1.00___secbench_eval/report.jsonl | wc -l)
    FAIL_FIX_O3=$(jq -r 'select(.reason | contains("FAIL_STEP: Run PoC")) | .reason' trajectories/${id}/secbench__o3-mini__t-0.00__p-0.95__c-1.00___secbench_eval/report.jsonl | wc -l)

    # Calculate percentages
    SUCCESS_PERC_O3=$(echo "scale=2; $SUCCESS_O3 * 100 / $TOTAL_O3" | bc)
    NO_PATCH_PERC_O3=$(echo "scale=2; $NO_PATCH_O3 * 100 / $TOTAL_O3" | bc)
    GIT_PERC_O3=$(echo "scale=2; $GIT_O3 * 100 / $TOTAL_O3" | bc)
    COMPILE_PERC_O3=$(echo "scale=2; $COMPILE_O3 * 100 / $TOTAL_O3" | bc)
    FAIL_FIX_PERC_O3=$(echo "scale=2; $FAIL_FIX_O3 * 100 / $TOTAL_O3" | bc)

    # Display results
    echo -e "\e[1;32mSuccess: $SUCCESS_O3/$TOTAL_O3 ($SUCCESS_PERC_O3%)\e[0m"
    echo "No Patch: $NO_PATCH_O3/$TOTAL_O3 ($NO_PATCH_PERC_O3%)"
    echo "Patch Format Error: $GIT_O3/$TOTAL_O3 ($GIT_PERC_O3%)"
    echo "Compile Error: $COMPILE_O3/$TOTAL_O3 ($COMPILE_PERC_O3%)"
    echo "Fail to Fix: $FAIL_FIX_O3/$TOTAL_O3 ($FAIL_FIX_PERC_O3%)"
fi
