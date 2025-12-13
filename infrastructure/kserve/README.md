# KServe Model Serving Infrastructure

This directory contains the configuration to deploy the fraud detection model as a production API using KServe.

## 🏗️ Architecture

The architecture establishes a bridge between the stored model in MLflow/MinIO and the production API:

1.  **Storage (MinIO)**: The trained model artifacts are stored in the `mlflow-bucket`.
2.  **Identity (ServiceAccount)**: KServe requires permissions to access MinIO for model downloading. A `ServiceAccount` is configured with a `Secret` containing the necessary credentials.
3.  **Service (InferenceService)**: The inference service orchestrates the model deployment. It downloads the model artifacts, initializes the server (`mlserver`), and exposes an HTTP endpoint for predictions.

## ⚠️ Configuration Notes (NumPy Compatibility)

The deployment is configured to address compatibility issues with models trained using NumPy 2.0+. The default `sklearn-server` is replaced with the **MLflow Runtime (MLServer)**.

- **Model Format**: `mlflow` (Version 1)
- **Protocol**: `v2` (Modern KServe protocol)

## 📂 File Guide

- **`storage-secret.yaml`** 🔐
  - Contains MinIO user/password credentials.
  - **Purpose**: Enables KServe to authenticate and download model files from S3 storage.

- **`serviceaccount.yaml`** 🆔
  - Defines the identity used by KServe pods within the cluster.
  - **Purpose**: Attaches the `storage-secret` to the pods, granting retrieval permissions.

- **`inferenceservice.yaml`** 🤖
  - Defines the model server and API configuration.
  - **Configuration**:
    - Specifies the **direct path** to model artifacts in MinIO.
    - Configures the `mlflow` runtime environment.
    - Sets the protocol version to `v2`.

---

## 🚀 Quick Deployment

```bash
# Deploy all KServe resources automatically
bash scripts/deploy-kserve.sh
```

## 🛠️ Manual Deployment Steps

To deploy resources individually:

```bash
# 1. Create storage secret
kubectl apply -f infrastructure/kserve/storage-secret.yaml

# 2. Create ServiceAccount
kubectl apply -f infrastructure/kserve/serviceaccount.yaml

# 3. Deploy InferenceService
kubectl apply -f infrastructure/kserve/inferenceservice.yaml

# 4. Check status
kubectl get inferenceservices -n kubeflow-user-example-com
kubectl get pods -n kubeflow-user-example-com | grep fraud-detection
```

## 🧪 Testing

Once deployed, the model can be tested using the provided Python script:

```bash
# 1. Open a tunnel to the service (in a separate terminal)
kubectl port-forward -n kubeflow-user-example-com svc/fraud-detection-predictor-default 8080:80

# 2. Run the test script
python3 examples/test_inference.py
```

### Test Output Interpretation
The test script sends 5 sample transactions (a mix of "normal-like" and "fraud-like" patterns).
- **Low Probability** (e.g., 0.05): Indicates a normal transaction.
- **High Probability** (e.g., 0.95): Indicates a fraudulent transaction.

## 🔄 Updating the Model

The InferenceService uses a direct S3 path to the model artifacts:
`s3://mlflow-bucket/1/models/m-89290d7b6b034916a37ba734b272a672/artifacts`

To update to a new model version:
1.  Identify the new Run ID and Artifact path in the MLflow UI.
2.  Update the `storageUri` field in `inferenceservice.yaml`.
3.  Apply the changes: `kubectl apply -f infrastructure/kserve/inferenceservice.yaml`.
