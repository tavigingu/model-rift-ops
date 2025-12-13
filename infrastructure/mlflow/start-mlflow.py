#!/usr/bin/env python3
"""
MLflow server startup script that ensures boto3 can see AWS credentials.
"""
import os
import sys
import subprocess

# Force AWS credentials into environment before any imports
os.environ['AWS_ACCESS_KEY_ID'] = os.environ.get('AWS_ACCESS_KEY_ID', '')
os.environ['AWS_SECRET_ACCESS_KEY'] = os.environ.get('AWS_SECRET_ACCESS_KEY', '')
os.environ['AWS_DEFAULT_REGION'] = 'us-east-1'
os.environ['AWS_REGION'] = 'us-east-1'

# Verify credentials are set
if not os.environ['AWS_ACCESS_KEY_ID']:
    print("ERROR: AWS_ACCESS_KEY_ID not set!", file=sys.stderr)
    sys.exit(1)

print(f"Starting MLflow with AWS credentials: {os.environ['AWS_ACCESS_KEY_ID'][:5]}...", flush=True)

# Build MLflow command
backend_store_uri = os.environ.get('MLFLOW_BACKEND_STORE_URI')
if not backend_store_uri:
    print("ERROR: MLFLOW_BACKEND_STORE_URI not set!", file=sys.stderr)
    sys.exit(1)

cmd = [
    'mlflow', 'server',
    '--host=0.0.0.0',
    '--port=5000',
    f'--backend-store-uri={backend_store_uri}',
    '--artifacts-destination=s3://mlflow-bucket',
    '--default-artifact-root=mlflow-artifacts:/',
    '--serve-artifacts',
    '--allowed-hosts=*'
]

print(f"Executing: {' '.join(cmd)}", flush=True)

# Execute MLflow server
os.execvp('mlflow', cmd)
