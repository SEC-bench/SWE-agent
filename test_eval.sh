#!/bin/bash

# Get the user ID
id=$(whoami)
python run_eval.py --input-file trajectories/${id}/20250418/secbench__anthropic/claude-3-7-sonnet-20250219__t-0.00__p-0.95__c-1.50___secbench_test/preds.json --mode all
python run_eval.py --input-file trajectories/${id}/20250418/secbench__gpt-4o__t-0.00__p-0.95__c-1.00___secbench_test/preds.json
python run_eval.py --input-file trajectories/${id}/20250418/secbench__o3-mini__t-0.00__p-0.95__c-1.00___secbench_test/preds.json
# python run_eval.py --input-file trajectories/${id}/20250418/secbench__openai/gemini-2.5-pro-preview-03-25__t-0.00__p-0.95__c-1.00___secbench_test/preds.json