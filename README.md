# ML Infrastructure

Infrastructure setup for MLflow with MinIO and PostgreSQL on Kubernetes.

## ⚠️ Security Setup

**IMPORTANT:** This project contains sensitive credentials that must NOT be committed to Git.

### Before First Commit:

1. **Create secrets files from templates:**
   ```bash
   # Copy templates and fill in your actual credentials
   cp infrastructure/mlflow/secrets.yaml.template infrastructure/mlflow/secrets.yaml
   cp infrastructure/minio/secrets.yaml.template infrastructure/minio/secrets.yaml
   cp infrastructure/postgres/secrets.yaml.template infrastructure/postgres/secrets.yaml
   cp examples/test_mflow.py.template examples/test_mflow.py
   ```

2. **Edit each `secrets.yaml` file** and replace placeholders like `<YOUR_POSTGRES_PASSWORD>` with actual values.

3. **Never commit:**
   - `**/secrets.yaml` files (already in `.gitignore`)
   - `flow.txt` (contains logs with passwords)
   - `venv/` directory

### Additional Security Measures:

1. **Use Kubernetes Secrets properly:**
   - Consider using sealed-secrets or external secrets management
   - Use base64 encoded values in production
   - Rotate credentials regularly

2. **Environment Variables:**
   - Use `.env` files locally (already gitignored)
   - Use Kubernetes ConfigMaps for non-sensitive data

3. **Best Practices:**
   - Use different credentials for dev/staging/prod
   - Enable RBAC in Kubernetes
   - Use network policies to restrict access
   - Regularly audit secret access

## Usage

See individual component documentation in `infrastructure/` directories.
