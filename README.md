# MLflow on MicroK8s - Infrastructure as Code

**Simple, production-ready MLflow deployment on MicroK8s with PostgreSQL backend and MinIO S3 storage.**

---

## 🎯 What We Have Now

✅ **MLflow** - Experiment tracking and model registry  
✅ **PostgreSQL** - Metadata and experiment storage  
✅ **MinIO** - S3-compatible artifact storage  
✅ **Tested & Working** - All components verified

---

## 🚀 Quick Start

### 1. Prerequisites

- MicroK8s installed and running
- kubectl configured for MicroK8s
- Python 3.8+ with venv (for testing)

### 2. Create Secrets

```bash
# Copy templates and add your credentials
cp infrastructure/postgres/secrets.yaml.template infrastructure/postgres/secrets.yaml
cp infrastructure/minio/secrets.yaml.template infrastructure/minio/secrets.yaml
cp infrastructure/mlflow/secrets.yaml.template infrastructure/mlflow/secrets.yaml

# Edit secrets with your passwords (defaults work for testing)
```

### 3. Deploy MLflow Stack

```bash
# Create namespace
kubectl apply -f infrastructure/namespaces/mlflow-namespace.yaml

# Deploy PostgreSQL
kubectl apply -f infrastructure/postgres/

# Deploy MinIO
kubectl apply -f infrastructure/minio/

# Deploy MLflow
kubectl apply -f infrastructure/mlflow/

# Wait for pods to be ready
kubectl get pods -n mlflow -w
```

### 4. Access Services (Local Development)

```bash
# Port-forward MLflow UI
kubectl port-forward -n mlflow svc/mlflow-service 5000:5000 &

# Port-forward MinIO Console
kubectl port-forward -n mlflow svc/minio 9001:9001 &

# Port-forward MinIO S3 API
kubectl port-forward -n mlflow svc/minio 9000:9000 &
```

Access:
- **MLflow UI**: http://localhost:5000
- **MinIO Console**: http://localhost:9001 (credentials: minioadmin/minioadmin123)

### 5. Test Integration

```bash
# Create test script from template
cp examples/test_mlflow.py.template test_mlflow.py

# Setup Python environment
python3 -m venv venv
source venv/bin/activate
pip install mlflow scikit-learn boto3

# Run integration test
python test_mlflow.py
```

---

## 📁 Project Structure

```
ml-infrastructure/
├── infrastructure/
│   ├── namespaces/          # Kubernetes namespaces
│   ├── postgres/            # PostgreSQL deployment
│   ├── minio/               # MinIO S3 storage
│   └── mlflow/              # MLflow server
├── examples/
│   └── test_mlflow.py.template  # Integration test template
├── scripts/
│   └── start-all.sh.template    # Automated deployment script
└── README.md
```

---

## 🔧 Configuration

Default credentials (change for production!):

- **PostgreSQL**: `mlflow` / `mlflow123`
- **MinIO**: `minioadmin` / `minioadmin123`

See `.env.example` for all configurable values.

---

## ✅ Current Status - Stable Checkpoint

**Date**: December 12, 2025  
**Status**: ✅ **STABLE - MLflow Stack Working**

- [x] PostgreSQL metadata storage
- [x] MinIO artifact storage  
- [x] MLflow model registry
- [x] Full integration tested

---

## 🔜 Next Steps - Kubeflow Integration

Following guide: https://dev.to/prezaei/integrating-mlflow-with-kubeflow-revised-edition-3mf

### Planned:

1. Install Kubeflow v1.8 (clean installation)
2. Verify Kubeflow Dashboard accessible
3. Create MLflow VirtualService in Istio
4. Add MLflow tab to Kubeflow UI
5. Test full workflow: Kubeflow → Jupyter → MLflow

---

## 📝 Notes

- Using **MicroK8s** on bare metal (not Minikube)
- All services run in `mlflow` namespace
- Secrets are gitignored - use templates to create them
- Port-forwarding used for local access (production would use Ingress/LoadBalancer)

---

## 🐛 Troubleshooting

### Check Pod Status
```bash
kubectl get pods -n mlflow
kubectl describe pod <pod-name> -n mlflow
kubectl logs <pod-name> -n mlflow
```

### Verify Secrets
```bash
kubectl get secrets -n mlflow
```

### Test Database Connection
```bash
kubectl exec -n mlflow deployment/mlflow -- python -c "import psycopg2; print('OK')"
```

---

## 📚 References

- [MLflow Documentation](https://mlflow.org/docs/latest/index.html)
- [Integrating MLflow with Kubeflow](https://dev.to/prezaei/integrating-mlflow-with-kubeflow-revised-edition-3mf)
- [MinIO Documentation](https://min.io/docs/minio/kubernetes/upstream/)