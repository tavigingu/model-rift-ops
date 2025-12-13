#!/bin/bash
set -e

echo "🚀 Deploying KServe InferenceService for Fraud Detection Model"
echo "================================================================"

NAMESPACE="kubeflow-user-example-com"
KSERVE_DIR="$(dirname "$0")/../infrastructure/kserve"

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    echo "❌ Namespace $NAMESPACE does not exist!"
    echo "Please create it first or use the correct namespace."
    exit 1
fi

echo ""
echo "📦 Step 1: Creating storage secret..."
kubectl apply -f "$KSERVE_DIR/storage-secret.yaml"

echo ""
echo "👤 Step 2: Creating ServiceAccount..."
kubectl apply -f "$KSERVE_DIR/serviceaccount.yaml"

echo ""
echo "🤖 Step 3: Deploying InferenceService..."
kubectl apply -f "$KSERVE_DIR/inferenceservice.yaml"

echo ""
echo "⏳ Step 4: Waiting for InferenceService to be ready..."
echo "This may take a few minutes while the model is downloaded and loaded..."

# Wait for InferenceService to be ready (timeout after 5 minutes)
timeout=300
elapsed=0
while [ $elapsed -lt $timeout ]; do
    status=$(kubectl get inferenceservice fraud-detection -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
    
    if [ "$status" == "True" ]; then
        echo "✅ InferenceService is READY!"
        break
    fi
    
    echo "   Status: $status (waiting... ${elapsed}s/${timeout}s)"
    sleep 10
    elapsed=$((elapsed + 10))
done

if [ $elapsed -ge $timeout ]; then
    echo "⚠️  Timeout waiting for InferenceService to be ready"
    echo "Check the status with: kubectl get inferenceservice fraud-detection -n $NAMESPACE"
    echo "Check pod logs with: kubectl logs -n $NAMESPACE -l serving.kserve.io/inferenceservice=fraud-detection"
    exit 1
fi

echo ""
echo "📊 InferenceService Status:"
kubectl get inferenceservice fraud-detection -n "$NAMESPACE"

echo ""
echo "🔍 Predictor Pods:"
kubectl get pods -n "$NAMESPACE" -l serving.kserve.io/inferenceservice=fraud-detection

echo ""
echo "🌐 Service Endpoint:"
kubectl get svc -n "$NAMESPACE" | grep fraud-detection

echo ""
echo "================================================================"
echo "✅ Deployment Complete!"
echo ""
echo "To test the endpoint locally, run:"
echo "  kubectl port-forward -n $NAMESPACE svc/fraud-detection-predictor-default 8080:80"
echo ""
echo "Then test with:"
echo "  python3 examples/test_inference.py"
echo ""
