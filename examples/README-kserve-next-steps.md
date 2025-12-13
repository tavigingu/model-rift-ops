# Next Steps: Model Serving with KServe

This guide explains how to deploy your MLflow-registered fraud detection model as a production API using KServe on Kubernetes.

## 1. Find Your Model in MLflow Registry
- Open the MLflow UI (e.g., http://172.20.10.2:31178/mlflow/)
- Note the model name (e.g., `fraud-detection-demo`), version, and run ID

## 2. Create a KServe InferenceService YAML
Example (`inferenceservice.yaml`):
```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: fraud-detection
  namespace: kubeflow-user-example-com
spec:
  predictor:
    mlflow:
      modelUri: "models:/fraud-detection-demo/Production"
      # or: "models:/fraud-detection-demo/1"
      storageUri: ""
      resources:
        requests:
          cpu: 500m
          memory: 1Gi
```

## 3. Deploy the InferenceService
```sh
kubectl apply -f inferenceservice.yaml -n kubeflow-user-example-com
```

## 4. Check Service Status
```sh
kubectl get inferenceservices -n kubeflow-user-example-com
kubectl get pods -n kubeflow-user-example-com
```
Wait for the service to be READY.

## 5. Find the Public Endpoint
- If using Istio Gateway, the endpoint will look like:
  `http://<IP>:<PORT>/v1/models/fraud-detection:predict`
- Check with:
  ```sh
  kubectl get svc -n istio-system
  ```

## 6. Test the Prediction Endpoint
Example Python request:
```python
import requests
import numpy as np

data = {
    "instances": [np.random.randn(29).tolist()]
}
response = requests.post(
    "http://<IP>:<PORT>/v1/models/fraud-detection:predict",
    json=data
)
print(response.json())
```

## 7. (Optional) Automate Retraining & Redeploy
- Use a Kubernetes CronJob to retrain and register new models on a schedule.
- KServe can automatically serve the latest Production model.

---

For more details, see the main project documentation or KServe official docs.