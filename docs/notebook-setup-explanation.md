# Explicație Setup Notebook Kubeflow cu MLflow

## Ce ai făcut cu YAML-urile

### 1. **mlflow-notebook.yaml** - Crearea Notebook-ului
Acest fișier definește un **Notebook Jupyter** ca resursă custom Kubernetes (CRD de tip `Notebook` din Kubeflow).

#### Componentele principale:

```yaml
apiVersion: kubeflow.org/v1
kind: Notebook
```
- Acesta este un tip de resursă custom Kubeflow
- Kubeflow are un **Notebook Controller** care monitorizează resursele de tip `Notebook`
- Când creezi un Notebook, controller-ul:
  1. Creează un StatefulSet
  2. Creează un Service pentru a expune Jupyter
  3. Configurează routing-ul prin Istio
  4. Adaugă automat un Istio sidecar proxy

#### Ce face notebook-ul tău:

1. **Creează un PVC** (PersistentVolumeClaim):
   - 10Gi storage pentru workspace-ul Jupyter
   - Păstrează codul și datele între restart-uri

2. **Rulează un container Jupyter**:
   - Imagine: `jupyter/scipy-notebook:latest`
   - Are Python, NumPy, Pandas, Matplotlib, etc. preinstalate
   - **IMPORTANT**: Configurat cu `base_url` pentru a funcționa cu routing-ul Kubeflow:
     ```yaml
     args:
       - "--NotebookApp.base_url=/notebook/user-example-com/mlflow-test-notebook"
       - "--NotebookApp.allow_origin='*'"
       - "--NotebookApp.disable_check_xsrf=True"
     ```
   - Acest `base_url` trebuie să corespundă cu path-ul din VirtualService Istio

3. **Injectează variabile de mediu pentru MLflow**:
   ```yaml
   - name: MLFLOW_TRACKING_URI
     value: "http://mlflow-service.mlflow.svc.cluster.local:5000"
   ```
   - Notebook-ul știe automat unde este MLflow
   - Nu trebuie să configurezi manual în cod

4. **Setează credențiale S3/MinIO**:
   - MLflow poate salva artifacte (modele, plots, etc.) în MinIO
   - Credențialele sunt deja setate

### 2. **disable-auth-local.yaml** - Fix pentru Autentificare
Acest fișier rezolvă 2 probleme:

#### Problema 1: Lipsa user-ului autentificat
Kubeflow necesită header `kubeflow-userid` pentru a identifica utilizatorul:
```lua
request_handle:headers():add("kubeflow-userid", "user@example.com")
```

#### Problema 2: CSRF Token (problema ta)
Jupyter folosește CSRF protection:
- La prima accesare, Jupyter setează un cookie `_xsrf`
- La fiecare request ulterior, Jupyter verifică dacă primește header-ul `X-XSRFToken` care corespunde cu cookie-ul
- **Fix-ul**: Codul Lua extrage cookie-ul `_xsrf` și îl pune în header-ul `X-XSRFToken`:

```lua
local cookie = request_handle:headers():get("cookie")
if cookie then
  local xsrf = string.match(cookie, "_xsrf=([^;]+)")
  if xsrf then
    request_handle:headers():add("X-XSRFToken", xsrf)
  end
end
```

### 3. **PodSecurity Issue** (fixat)
Problema apărea pentru că:
- Istio injectează un init container (`istio-init`) care configurează iptables
- Necesită capabilități `NET_ADMIN` și `NET_RAW`
- Namespace-ul `user-example-com` avea politică `baseline` care bloca asta

**Fix aplicat**:
```bash
kubectl label namespace user-example-com pod-security.kubernetes.io/enforce=privileged --overwrite
```

## Ce să faci acum

### 1. Accesează Notebook-ul
Deschide browser-ul la:
```
http://10.99.67.204/jupyter/
```

În interfața Kubeflow:
1. Mergi la secțiunea **Notebooks**
2. Vei vedea `mlflow-test-notebook` în stare **Running**
3. Click pe **CONNECT** pentru a deschide Jupyter

### 2. Testează Integrarea MLflow
În notebook, creează o celulă nouă și testează:

```python
import mlflow
import os

# Verifică configurația (variabilele sunt deja setate!)
print(f"MLflow Tracking URI: {os.getenv('MLFLOW_TRACKING_URI')}")
print(f"S3 Endpoint: {os.getenv('MLFLOW_S3_ENDPOINT_URL')}")
print(f"Experiment: {os.getenv('MLFLOW_EXPERIMENT_NAME')}")

# Testează conexiunea
mlflow.set_experiment("kubeflow-experiments")
print("✓ Conectat la MLflow!")
```

### 3. Run un Experiment Simplu

```python
import mlflow
import mlflow.sklearn
from sklearn.linear_model import LinearRegression
from sklearn.datasets import make_regression
from sklearn.model_selection import train_test_split

# Creează date de test
X, y = make_regression(n_samples=100, n_features=10, noise=0.1)
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2)

# Pornește un run MLflow
with mlflow.start_run(run_name="kubeflow-test"):
    # Antrenează modelul
    model = LinearRegression()
    model.fit(X_train, y_train)
    score = model.score(X_test, y_test)
    
    # Log metrics
    mlflow.log_metric("r2_score", score)
    
    # Log model
    mlflow.sklearn.log_model(model, "linear_regression_model")
    
    print(f"Model antrenat! R² Score: {score:.4f}")
```

### 4. Verifică în MLflow UI
După ce rulezi experimentul:
```bash
# Forward MLflow UI
kubectl port-forward -n mlflow svc/mlflow-service 5000:5000
```

Apoi deschide: `http://localhost:5000`
- Vei vedea experimentul `kubeflow-experiments`
- Metrics, parametri, și modelul salvat

## Arhitectura Completă

```
Browser (http://10.99.67.204)
    ↓
Istio Ingress Gateway
    ↓ (adaugă kubeflow-userid + propagă CSRF)
EnvoyFilter (disable-auth-local.yaml)
    ↓
Kubeflow Central Dashboard
    ↓
Jupyter Notebook Service
    ↓ (injectat Istio sidecar)
Notebook Pod (mlflow-test-notebook-0)
    ├─ Jupyter Container
    │   └─ MLflow Client (conectat la MLflow)
    └─ Istio Proxy Sidecar
        ↓
    MLflow Service (namespace: mlflow)
        ├─ Tracking Server
        ├─ PostgreSQL (metadata)
        └─ MinIO (artifacte)
```

## Comenzi Utile

```bash
# Verifică starea notebook-ului
kubectl get notebooks -n user-example-com

# Verifică pod-ul
kubectl get pods -n user-example-com

# Vezi logs Jupyter
kubectl logs mlflow-test-notebook-0 -n user-example-com -c mlflow-test-notebook

# Vezi logs Istio sidecar
kubectl logs mlflow-test-notebook-0 -n user-example-com -c istio-proxy

# Accesează terminal în notebook
kubectl exec -it mlflow-test-notebook-0 -n user-example-com -c mlflow-test-notebook -- bash

# Șterge notebook-ul
kubectl delete notebook mlflow-test-notebook -n user-example-com
```

## Troubleshooting

### Dacă notebook-ul nu pornește:
```bash
kubectl describe notebook mlflow-test-notebook -n user-example-com
kubectl describe pod mlflow-test-notebook-0 -n user-example-com
```

### Dacă ai din nou eroare CSRF:
```bash
# Verifică că EnvoyFilter este aplicat
kubectl get envoyfilter -n istio-system

# Restart Istio ingress gateway
kubectl rollout restart deployment/istio-ingressgateway -n istio-system
```

### Dacă MLflow nu se conectează:
```bash
# Test din interiorul pod-ului
kubectl exec -it mlflow-test-notebook-0 -n user-example-com -c mlflow-test-notebook -- \
  curl http://mlflow-service.mlflow.svc.cluster.local:5000/health
```

## Next Steps

1. **Instalează pachete Python adiționale** în notebook:
   ```python
   !pip install tensorflow pytorch scikit-optimize
   ```

2. **Creează mai multe experimente** pentru diferite modele

3. **Explorează PodDefaults** pentru a injecta automat configurații în toate notebook-urile

4. **Setup CI/CD** pentru a rula antrenarea în pipeline-uri Kubeflow
