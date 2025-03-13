#!/bin/bash
# Check if mode argument is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <mode>"
    echo "Mode can be 'infer' or 'eval'"
    exit 1
fi

mode="$1"

# Validate mode argument
if [ "$mode" != "infer" ] && [ "$mode" != "eval" ]; then
    echo "Error: Mode must be either 'infer' or 'eval'"
    exit 1
fi

if [ "$mode" == "infer" ]; then
    ./run_infer.sh -m o3 -c 1.0 -t 0.0 -s test -l :10 -n 75 -b "https://litellm-proxy-153298433405.us-east1.run.app/"
    ./run_infer.sh -m 4o -c 1.0 -t 0.0 -s test -l :10 -n 75 -b "https://litellm-proxy-153298433405.us-east1.run.app/"
    ./run_infer.sh -m sonnet -c 1.5 -t 0.0 -s test -l :10 -n 75 -b "https://litellm-proxy-153298433405.us-east1.run.app/"
elif [ "$mode" == "eval" ]; then
    # Get the user ID
    id=$(whoami)
    python run_eval.py --input-file trajectories/${id}/secbench__claude-3-5-sonnet-20241022__t-0.00__p-0.95__c-1.50___secbench_test/preds.json
    python run_eval.py --input-file trajectories/${id}/secbench__gpt-4o__t-0.00__p-0.95__c-1.00___secbench_test/preds.json
    python run_eval.py --input-file trajectories/${id}/secbench__o3-mini__t-0.00__p-0.95__c-1.00___secbench_test/preds.json
fi
