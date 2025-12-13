# MLflow Serve-Artifacts with MinIO: InvalidAccessKeyId Error

## Problem Description

When using MLflow with `--serve-artifacts` mode and MinIO as the artifact store, experiments fail with:

```
S3UploadFailedError: Failed to upload /tmp/.../model.pkl to mlflow-bucket/...: 
An error occurred (InvalidAccessKeyId) when calling the PutObject operation: 
The Access Key Id you provided does not exist in our records.
```

## Root Cause

**boto3 does NOT automatically inherit environment variables when invoked from within the MLflow Python process.**

Even when AWS credentials are set as Kubernetes environment variables, boto3 creates S3 clients at runtime without seeing those credentials because:
1. Environment variables are set in the shell/container context
2. MLflow server starts as a Python process
3. boto3 is imported and initialized AFTER the Python interpreter starts
4. By that time, boto3's credential chain doesn't find the env vars

## Failed Attempts

### ❌ Setting env vars in Kubernetes Deployment
```yaml
env:
  - name: AWS_ACCESS_KEY_ID
    valueFrom: {secretKeyRef: ...}
```
**Why it failed:** boto3 doesn't see them at runtime

### ❌ Creating ~/.aws/credentials file
```bash
cat > ~/.aws/credentials <<EOF
[default]
aws_access_key_id = minioadmin
aws_secret_access_key = minioadmin123
EOF
```
**Why it failed:** boto3 ignores this in MLflow context

### ❌ Exporting vars in shell script
```bash
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}"
exec mlflow server ...
```
**Why it failed:** Too late - boto3 already initialized

## Solution: Python Wrapper Script

Create a Python wrapper that **forces environment variables into os.environ BEFORE any boto3 imports occur:**

### 1. Create `start-mlflow.py`:
```python
#!/usr/bin/env python3
import os
import sys

# Force AWS credentials into environment BEFORE any boto3 imports
os.environ['AWS_ACCESS_KEY_ID'] = os.environ.get('AWS_ACCESS_KEY_ID', '')
os.environ['AWS_SECRET_ACCESS_KEY'] = os.environ.get('AWS_SECRET_ACCESS_KEY', '')
os.environ['AWS_DEFAULT_REGION'] = 'us-east-1'
os.environ['AWS_REGION'] = 'us-east-1'

# Verify credentials are set
if not os.environ['AWS_ACCESS_KEY_ID']:
    print("ERROR: AWS_ACCESS_KEY_ID not set!", file=sys.stderr)
    sys.exit(1)

print(f"Starting MLflow with AWS credentials: {os.environ['AWS_ACCESS_KEY_ID'][:5]}...", flush=True)

# Build and execute MLflow command
backend_store_uri = os.environ.get('MLFLOW_BACKEND_STORE_URI')
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

os.execvp('mlflow', cmd)  # Replace process (not subprocess)
```

### 2. Mount script via ConfigMap:
```bash
kubectl create configmap -n mlflow mlflow-startup-script \
  --from-file=start-mlflow.py
```

### 3. Update Deployment:
```yaml
spec:
  volumes:
    - name: startup-script
      configMap:
        name: mlflow-startup-script
        defaultMode: 0755
  containers:
  - name: mlflow
    volumeMounts:
      - name: startup-script
        mountPath: /app/start-mlflow.py
        subPath: start-mlflow.py
    env:
      - name: AWS_ACCESS_KEY_ID
        valueFrom: {secretKeyRef: ...}
      - name: AWS_SECRET_ACCESS_KEY
        valueFrom: {secretKeyRef: ...}
      - name: MLFLOW_S3_ENDPOINT_URL
        value: "http://minio.mlflow.svc.cluster.local:9000"
    command: ["sh", "-c"]
    args:
      - |
        export MLFLOW_BACKEND_STORE_URI="postgresql+psycopg2://..."
        exec python3 /app/start-mlflow.py
```

## Correct MLflow Scenario 5 Configuration

### Server Side:
```bash
mlflow server \
  --backend-store-uri=postgresql://user:pass@host/db \
  --artifacts-destination=s3://mlflow-bucket \      # Real storage location
  --default-artifact-root=mlflow-artifacts:/ \      # Virtual proxy scheme
  --serve-artifacts                                  # Server handles uploads
```

**Critical requirements:**
- `--artifacts-destination`: Actual S3/MinIO bucket path
- `--default-artifact-root`: Must be `mlflow-artifacts:/` for proxied access
- Credentials MUST be in environment variables of the MLflow process
- `MLFLOW_S3_ENDPOINT_URL` required for MinIO (not AWS S3)

### Client Side:
```python
import mlflow

mlflow.set_tracking_uri("http://mlflow-server:5000")

# Create NEW experiment (old experiments have immutable artifact_location)
mlflow.create_experiment("my-new-experiment")
mlflow.set_experiment("my-new-experiment")

# DO NOT set AWS credentials in client code!
with mlflow.start_run():
    mlflow.sklearn.log_model(model, "model")  # Server handles upload
```

**Client rules:**
- ❌ DO NOT set `os.environ["AWS_ACCESS_KEY_ID"]` in notebooks
- ❌ DO NOT set `os.environ["MLFLOW_S3_ENDPOINT_URL"]` in notebooks
- ✅ DO create NEW experiments (old ones have wrong artifact_location)
- ✅ DO let the server handle all artifact uploads

## Why Old Experiments Don't Work

When you create an MLflow experiment, the `artifact_location` is **permanently saved in the database**:

- **Old experiment:** `artifact_location = "s3://mlflow-bucket/1"`
  - Client tries to upload directly to S3 → ❌ FAILS (no credentials)
  
- **New experiment:** `artifact_location = "mlflow-artifacts:/3"`
  - Client sends artifacts to server → Server uploads to S3 → ✅ SUCCESS

**You cannot change artifact_location for existing experiments** - you must create new ones.

## Architecture Flow

```
Jupyter Notebook → MLflow Server → MinIO/S3
    (client)     (mlflow-artifacts:/)  (s3://bucket)

1. Notebook: mlflow.log_model() → sends artifacts to server
2. Server: receives artifacts → boto3 uploads to s3://mlflow-bucket
3. MinIO: stores in bucket
```

## Key Lessons

1. **boto3 credential resolution is tricky** - env vars must be set BEFORE Python process starts
2. **Python wrapper > shell export** - only way to guarantee boto3 sees credentials
3. **--serve-artifacts changes workflow** - clients no longer upload directly
4. **Experiments are immutable** - artifact_location cannot be changed after creation
5. **Use mlflow-artifacts:/ scheme** - signals proxied access to clients

## Testing the Solution

### Verify server has credentials:
```bash
kubectl logs -n mlflow deployment/mlflow | grep "Starting MLflow"
# Should show: Starting MLflow with AWS credentials: minio...
```

### Test from notebook:
```python
import mlflow

mlflow.set_tracking_uri("http://mlflow-service.mlflow.svc.cluster.local:5000")
mlflow.create_experiment("test-proxied-artifacts")
mlflow.set_experiment("test-proxied-artifacts")

# Verify artifact location
exp = mlflow.get_experiment_by_name("test-proxied-artifacts")
print(f"Artifact Location: {exp.artifact_location}")
# Should be: mlflow-artifacts:/X (not s3://...)

# Test model logging
with mlflow.start_run():
    mlflow.sklearn.log_model(model, "model")
    # Should succeed without any S3 errors!
```

## References

- [MLflow Scenario 5 Documentation](https://mlflow.org/docs/latest/tracking.html#scenario-5-mlflow-tracking-server-enabled-with-proxied-artifact-storage-access)
- [GitHub Issue #5514](https://github.com/mlflow/mlflow/issues/5514) - MinIO setup example
- [StackOverflow: Proxied artifact access](https://stackoverflow.com/questions/72886409/mlflow-proxied-artifact-access-unable-to-locate-credentials)
