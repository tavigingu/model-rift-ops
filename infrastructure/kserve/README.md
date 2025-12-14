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

- **`storage-secret.yaml.template`** 🔐
  - Template for MinIO credentials.
  - **Setup**: Copy to `storage-secret.yaml` and update credentials.
  - **Purpose**: Enables KServe to authenticate and download model files from S3 storage.

- **`serviceaccount.yaml`** 🆔
  - Defines the identity used by KServe pods within the cluster.
  - **Purpose**: Attaches the `storage-secret` to the pods, granting retrieval permissions.

---

## 🚀 Setup

```bash
# 1. Create storage secret from template
cp infrastructure/kserve/storage-secret.yaml.template infrastructure/kserve/storage-secret.yaml
# Edit storage-secret.yaml with your MinIO credentials

# 2. Apply resources
kubectl apply -f infrastructure/kserve/storage-secret.yaml
kubectl apply -f infrastructure/kserve/serviceaccount.yaml
```

## 📓 Model Deployment

Deploy models directly from notebooks using KServe Python SDK.

See complete workflow: [`examples/kserve-deployment-demo.ipynb`](../../examples/kserve-deployment-demo.ipynb)

## 🧪 Testing

Test the deployed model from within the notebook or using requests:

```python
import requests

response = requests.post(
    'http://fraud-detection-model-predictor.kubeflow-user-example-com.svc.cluster.local:80/v1/models/fraud-detection-model:predict',
    json={'instances': [[0.5, 1.2, -0.3, ...]]}  # Your features
)

predictions = response.json()['predictions']
print(f"Predictions: {predictions}")
```
