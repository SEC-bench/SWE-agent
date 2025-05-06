#!/bin/bash

# Default values
COST_LIMIT=0.2
TEMPERATURE=0.2
SPLIT="test"
SLICE=":1"
API_BASE=""
CALL_LIMIT=30
NUM_WORKERS=1

# Help function
show_help() {
    echo "Usage: $0 -m <model> -t <type> [-c <cost_limit>] [-e <temperature>] [-s <split>] [-l <slice>] [-b <api_base_url>] [-n <call_limit>] [-w <num_workers>]"
    echo "  -m: Model name (sonnet, haiku, 4o, o1, human)"
    echo "  -t: Type (secb_patch, secb_poc)"
    echo "  -c: Cost limit (default: 0.2)"
    echo "  -e: Temperature (default: 0.2)"
    echo "  -s: Split (default: cve)"
    echo "  -l: Slice (default: 1:2)"
    echo "  -b: API Base URL (optional)"
    echo "  -n: Per instance call limit (default: 30)"
    echo "  -w: Number of workers (default: 1)"
    echo "  -h: Show this help message"
    exit 1
}

# Parse command line arguments
while getopts "m:t:f:c:e:s:l:b:n:w:h" opt; do
    case $opt in
        m) MODEL="$OPTARG";;
        t) TYPE="$OPTARG";;
        f) CONFIG_FILE="$OPTARG";;
        c) COST_LIMIT="$OPTARG";;
        e) TEMPERATURE="$OPTARG";;
        s) SPLIT="$OPTARG";;
        l) SLICE="$OPTARG";;
        b) API_BASE="$OPTARG";;
        n) CALL_LIMIT="$OPTARG";;
        w) NUM_WORKERS="$OPTARG";;
        h) show_help;;
        \?) show_help;;
    esac
done

# Check if model is provided
if [ -z "$MODEL" ]; then
    echo "Error: Model (-m) is required"
    show_help
fi

# Check if config file is provided
if [ -z "$CONFIG_FILE" ]; then
    echo "Error: Config file (-f) is required"
    show_help
fi

# Check if type is provided
if [ -z "$TYPE" ]; then
    echo "Error: Type (-t) is required"
    show_help
fi

clear

if [ "$MODEL" == "sonnet" ]; then
    MODEL_NAME="anthropic/claude-3-7-sonnet-20250219"
    MAX_INPUT_TOKENS=200000
    # MODEL_NAME="claude-3-5-sonnet-20241022"
elif [ "$MODEL" == "haiku" ]; then
    # MODEL_NAME="claude-3-5-haiku-20241022"
    MODEL_NAME="claude-3-haiku-20240307"
elif [ "$MODEL" == "4o" ]; then
    MODEL_NAME="gpt-4o"
elif [ "$MODEL" == "o1" ]; then
    MODEL_NAME="o1-mini"
elif [ "$MODEL" == "o3" ]; then
    MODEL_NAME="o3-mini"
elif [ "$MODEL" == "gemini-pro" ]; then
    MODEL_NAME="gemini/gemini-2.5-pro-preview-03-25"
    # MAX_INPUT_TOKENS=1048576
    # MODEL_NAME="openai/gemini-1.5-pro"
    # MAX_INPUT_TOKENS=2097152
elif [ "$MODEL" == "flash" ]; then
    MODEL_NAME="openai/gemini-2.0-flash-exp"
    MAX_INPUT_TOKENS=1048576
elif [ "$MODEL" == "human" ]; then
    MODEL_NAME="human"
else
    echo "Invalid model: $MODEL"
    exit 1
fi

# For debug, run with an option, --agent.model.name human.

# Start building the command
CMD="sweagent run-batch \
    --num_workers $NUM_WORKERS \
    --config $CONFIG_FILE \
    --agent.model.name $MODEL_NAME \
    --agent.model.temperature $TEMPERATURE \
    --agent.model.top_p 0.95 \
    --agent.model.per_instance_call_limit $CALL_LIMIT \
    --agent.model.per_instance_cost_limit $COST_LIMIT \
    --agent.model.delay 1.0 \
    --instances.type $TYPE \
    --instances.dataset_name \"SEC-bench/SEC-bench\" \
    --instances.split $SPLIT \
    --instances.slice $SLICE \
    --instances.shuffle=False"

# Add API base URL if provided
if [ -n "$API_BASE" ]; then
    echo -e "\033[1;32mAdding API base URL: \033[1;33m$API_BASE\033[0m"
    CMD="$CMD \
    --agent.model.api_base $API_BASE"
fi

# Add max input tokens if provided
if [ -n "$MAX_INPUT_TOKENS" ]; then
    echo -e "\033[1;32mAdding max input tokens: \033[1;33m$MAX_INPUT_TOKENS\033[0m"
    CMD="$CMD \
    --agent.model.max_input_tokens $MAX_INPUT_TOKENS"
fi

# Execute the command
# echo -e "\033[32m$CMD\033[0m"
eval "$CMD"