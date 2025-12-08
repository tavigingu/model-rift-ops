#!/bin/bash
set -e

echo "🚀 Starting MLops Infrastructure..."

# 1. Pornește Minikube
echo "📦 Starting Minikube..."
sudo minikube start --driver=none --cpus=4 --memory=8192

# 2. Verifică că e gata
echo "✅ Checking cluster..."
kubectl get nodes

# 3. Instalează Istio (dacă nu e deja)
echo "🌐 Installing Istio..."
istioctl install --set profile=demo -y || echo "Istio already installed"

# 4. Instalează Kubeflow (dacă nu e deja)
echo "🔧 Installing Kubeflow..."
if ! kubectl get namespace kubeflow &> /dev/null; then
    cd ~/manifests
    while ! kustomize build example | kubectl apply -f -; do 
        echo "Retrying Kubeflow installation..."; 
        sleep 10; 
    done
    cd -
else
    echo "Kubeflow already installed"
fi

# 4.5 Aplică RBAC pentru Kubeflow
echo "🔐 Configuring Kubeflow RBAC..."
kubectl apply -f infrastructure/kubeflow/rbac.yaml

# Șterge politici restrictive (pentru development)
kubectl delete authorizationpolicy central-dashboard jupyter-web-app katib-ui ml-pipeline ml-pipeline-ui -n kubeflow 2>/dev/null || true

# 5. Aplică namespace MLflow
echo "📁 Creating namespace..."
kubectl apply -f infrastructure/namespaces/

# 6. Aplică PostgreSQL
echo "🐘 Deploying PostgreSQL..."
kubectl apply -f infrastructure/postgres/
sleep 10
kubectl wait --for=condition=ready pod -l app=mlflow-postgres -n mlflow --timeout=300s

# 7. Creează user și database în PostgreSQL
echo "👤 Creating PostgreSQL user and database..."
kubectl exec -n mlflow deployment/mlflow-postgres -- psql -U postgres -c "CREATE USER mlflow WITH PASSWORD 'mlflow123';" || true
kubectl exec -n mlflow deployment/mlflow-postgres -- psql -U postgres -c "CREATE DATABASE mlflow_db;" || true
kubectl exec -n mlflow deployment/mlflow-postgres -- psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE mlflow_db TO mlflow;" || true

# 8. Aplică MinIO
echo "🗄️  Deploying MinIO..."
kubectl apply -f infrastructure/minio/
sleep 10
kubectl wait --for=condition=ready pod -l app=minio -n mlflow --timeout=300s

# 9. Creează bucket în MinIO
echo "🪣 Creating MinIO bucket..."
kubectl port-forward svc/minio -n mlflow 9000:9000 &
PF_PID=$!
sleep 5
mc alias set mlflow-minio http://localhost:9000 minioadmin minioadmin123 || true
mc mb mlflow-minio/mlflow-bucket || true
kill $PF_PID

# 10. Aplică MLflow
echo "📊 Deploying MLflow..."
kubectl apply -f infrastructure/mlflow/
sleep 10
kubectl wait --for=condition=ready pod -l app=mlflow -n mlflow --timeout=300s

# 11. Configurează Istio Gateway și VirtualServices
echo "🌐 Configuring Istio routing..."
kubectl apply -f infrastructure/istio/

# 12. Obține IP
MINIKUBE_IP=$(minikube ip)
NODEPORT=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')

# 13. Status final
echo ""
echo "✅ ✅ ✅ All services are running! ✅ ✅ ✅"
echo ""
kubectl get pods -n mlflow
kubectl get pods -n kubeflow | head -10
echo ""
echo "🌐 Access services:"
echo "   Kubeflow:    http://$MINIKUBE_IP:$NODEPORT"
echo "   MLflow:      http://$MINIKUBE_IP:$NODEPORT/mlflow"
echo "   MinIO:       http://$MINIKUBE_IP:$NODEPORT/minio"
echo ""
echo "💡 For LoadBalancer (no port), run: minikube tunnel"