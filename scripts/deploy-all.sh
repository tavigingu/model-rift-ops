#!/bin/bash
set -e

echo "🚀 ML Infrastructure Deployment Script"
echo "======================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check prerequisites
echo "📋 Checking prerequisites..."

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl not found${NC}"
    exit 1
fi

if ! command -v kustomize &> /dev/null; then
    echo -e "${YELLOW}⚠️  kustomize not found. Installing...${NC}"
    # Install kustomize if needed
    curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
    sudo mv kustomize /usr/local/bin/
fi

echo -e "${GREEN}✅ Prerequisites OK${NC}"
echo ""

# Step 1: Deploy MLflow Stack
echo "📦 Step 1: Deploying MLflow Stack..."
echo "-----------------------------------"

# Check if secrets exist
if [ ! -f "infrastructure/postgres/secrets.yaml" ]; then
    echo -e "${YELLOW}⚠️  PostgreSQL secrets not found. Please create from template:${NC}"
    echo "   cp infrastructure/postgres/secrets.yaml.template infrastructure/postgres/secrets.yaml"
    exit 1
fi

if [ ! -f "infrastructure/minio/secrets.yaml" ]; then
    echo -e "${YELLOW}⚠️  MinIO secrets not found. Please create from template:${NC}"
    echo "   cp infrastructure/minio/secrets.yaml.template infrastructure/minio/secrets.yaml"
    exit 1
fi

if [ ! -f "infrastructure/mlflow/secrets.yaml" ]; then
    echo -e "${YELLOW}⚠️  MLflow secrets not found. Please create from template:${NC}"
    echo "   cp infrastructure/mlflow/secrets.yaml.template infrastructure/mlflow/secrets.yaml"
    exit 1
fi

echo "Creating mlflow namespace..."
kubectl apply -f infrastructure/namespaces/mlflow-namespace.yaml

echo "Deploying PostgreSQL..."
kubectl apply -f infrastructure/postgres/

echo "Deploying MinIO..."
kubectl apply -f infrastructure/minio/

echo "Deploying MLflow..."
kubectl apply -f infrastructure/mlflow/

echo "Waiting for MLflow pods to be ready..."
kubectl wait --for=condition=ready pod -l app=mlflow-postgres -n mlflow --timeout=120s
kubectl wait --for=condition=ready pod -l app=minio -n mlflow --timeout=120s
kubectl wait --for=condition=ready pod -l app=mlflow -n mlflow --timeout=120s

echo -e "${GREEN}✅ MLflow Stack deployed${NC}"
echo ""

# Step 2: Deploy Kubeflow
echo "📦 Step 2: Deploying Kubeflow..."
echo "--------------------------------"

MANIFESTS_DIR="${HOME}/manifests"

if [ ! -d "$MANIFESTS_DIR" ]; then
    echo "Cloning Kubeflow manifests..."
    cd ~
    git clone https://github.com/kubeflow/manifests.git
    cd manifests
    git checkout v1.8-branch
else
    echo "Kubeflow manifests already exist at $MANIFESTS_DIR"
    cd $MANIFESTS_DIR
fi

echo "Installing Kubeflow (this may take 5-10 minutes)..."
kustomize build example | kubectl apply -f -

echo "Waiting for Kubeflow pods..."
echo "(This might take a while. Press Ctrl+C to skip waiting and continue manually)"
kubectl wait --for=condition=ready pod -l app=centraldashboard -n kubeflow --timeout=600s || true

echo -e "${GREEN}✅ Kubeflow deployed${NC}"
echo ""

# Step 3: Configure Istio Gateway
echo "🌐 Step 3: Configuring Istio Gateway..."
echo "---------------------------------------"

echo "Patching istio-ingressgateway to NodePort..."
kubectl patch svc istio-ingressgateway -n istio-system -p '{"spec":{"type":"NodePort"}}'

NODEPORT=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

echo -e "${GREEN}✅ Istio Gateway exposed on NodePort${NC}"
echo -e "   Access URL: ${YELLOW}http://${NODE_IP}:${NODEPORT}${NC}"
echo ""

# Step 4: Integrate MLflow with Kubeflow
echo "🔗 Step 4: Integrating MLflow with Kubeflow..."
echo "-----------------------------------------------"

cd - > /dev/null  # Return to project directory

echo "Creating MLflow VirtualService..."
kubectl apply -f infrastructure/mlflow/istio/virtualservice.yaml

echo "Adding MLflow tab to Kubeflow Dashboard..."
kubectl patch cm centraldashboard-config -n kubeflow --type='json' \
  --patch-file infrastructure/kubeflow/dashboard-mlflow-patch.json

echo "Restarting centraldashboard..."
kubectl rollout restart deploy centraldashboard -n kubeflow

echo "Fixing CSRF issue for notebook creation..."
kubectl set env deployment/jupyter-web-app-deployment -n kubeflow APP_SECURE_COOKIES=false

echo -e "${GREEN}✅ MLflow integrated with Kubeflow${NC}"
echo ""

# Summary
echo "🎉 Deployment Complete!"
echo "======================"
echo ""
echo -e "📍 ${YELLOW}Kubeflow Dashboard:${NC} http://${NODE_IP}:${NODEPORT}"
echo -e "📍 ${YELLOW}MLflow UI:${NC}          http://${NODE_IP}:${NODEPORT}/mlflow/"
echo ""
echo -e "🔐 ${YELLOW}Default Credentials:${NC}"
echo "   Email:    user@example.com"
echo "   Password: 12341234"
echo ""
echo -e "📊 ${YELLOW}Next Steps:${NC}"
echo "   1. Access Kubeflow Dashboard"
echo "   2. Create a Jupyter Notebook (image: kubeflownotebookswg/jupyter-scipy:v1.8.0)"
echo "   3. Test MLflow integration with provided example code"
echo ""
echo -e "${GREEN}Happy ML Engineering! 🚀${NC}"
