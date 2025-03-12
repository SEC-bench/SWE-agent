#!/bin/bash

# Default values
COST_LIMIT=0.2
TEMPERATURE=0.2
SPLIT="test"
SLICE=":1"
API_BASE=""

# Help function
show_help() {
    echo "Usage: $0 -m <model> [-c <cost_limit>] [-t <temperature>] [-s <split>] [-l <slice>] [-b <api_base_url>]"
    echo "  -m: Model name (sonnet, haiku, 4o, o1, human)"
    echo "  -c: Cost limit (default: 0.2)"
    echo "  -t: Temperature (default: 0.2)"
    echo "  -s: Split (default: cve)"
    echo "  -l: Slice (default: 1:2)"
    echo "  -b: API Base URL (optional)"
    echo "  -h: Show this help message"
    exit 1
}

# Parse command line arguments
while getopts "m:c:t:s:l:b:h" opt; do
    case $opt in
        m) MODEL="$OPTARG";;
        c) COST_LIMIT="$OPTARG";;
        t) TEMPERATURE="$OPTARG";;
        s) SPLIT="$OPTARG";;
        l) SLICE="$OPTARG";;
        b) API_BASE="$OPTARG";;
        h) show_help;;
        \?) show_help;;
    esac
done

# Check if model is provided
if [ -z "$MODEL" ]; then
    echo "Error: Model (-m) is required"
    show_help
fi

clear

if [ "$MODEL" == "sonnet" ]; then
    # MODEL_NAME="claude-3-7-sonnet-20250219"
    MODEL_NAME="claude-3-5-sonnet-20241022"
elif [ "$MODEL" == "haiku" ]; then
    MODEL_NAME="claude-3-5-haiku-20241022"
elif [ "$MODEL" == "4o" ]; then
    MODEL_NAME="gpt-4o"
elif [ "$MODEL" == "o1" ]; then
    MODEL_NAME="o1-mini"
elif [ "$MODEL" == "o3" ]; then
    MODEL_NAME="o3-mini"
elif [ "$MODEL" == "gemini-pro" ]; then
    MODEL_NAME="gemini-1.5-pro"
elif [ "$MODEL" == "gemini-flash" ]; then
    MODEL_NAME="gemini-2.0-flash-exp"
elif [ "$MODEL" == "human" ]; then
    MODEL_NAME="human"
else
    echo "Invalid model: $MODEL"
    exit 1
fi

# For debug, run with an option, --agent.model.name human.

# Start building the command
CMD="sweagent run-batch \
    --config ./config/secbench.yaml \
    --agent.model.name $MODEL_NAME \
    --agent.model.temperature $TEMPERATURE \
    --agent.model.top_p 0.95 \
    --agent.model.per_instance_cost_limit $COST_LIMIT \
    --agent.model.delay 1.0 \
    --instances.type secbench \
    --instances.dataset_name \"hwiwonl/SEC-bench\" \
    --instances.split $SPLIT \
    --instances.slice $SLICE \
    --instances.shuffle=False"

# Add API base URL if provided
if [ -n "$API_BASE" ]; then
    CMD="$CMD \
    --agent.model.api_base $API_BASE"
fi

# Execute the command
# echo -e "\033[32m$CMD\033[0m"
eval "$CMD"