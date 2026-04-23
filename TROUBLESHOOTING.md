# Troubleshooting Guide

## Region and Quota Constraints

### AKS vCPU Quota Issues

Different regions have different available VM families and quotas. If you encounter quota errors during `terraform apply`:

1. **Check available quota in your region:**
   ```bash
   az vm list-usage --location <region> --output json | jq '.[] | select(.currentValue >= .limit) | .name.localizedValue'
   ```

2. **Adjust node VM size based on available quota:**
   - `centralindia` has tested compatibility with `Standard_F2as_v6`
   - Try smaller SKUs if quota is exhausted: `Standard_B2s_v2`, `Standard_F2s_v2`
   - Request quota increase in Azure Portal under Quotas

3. **Kubernetes version constraints:**
   - Kubernetes 1.34.x+ requires Premium AKS tier for LTS support (Free tier uses non-LTS versions)
   - Use `az aks get-versions --location <region>` to list supported versions in your region

### Example Fix for quota issues:

```hcl
# In terraform.tfvars, try:
kubernetes_version = "1.34.4"  # Known to work in centralindia
node_vm_size = "Standard_F2as_v6"  # Has available quota in centralindia
node_count = 1  # Start small; scale up after successful provisioning
```

## Docker and Container Issues

### Docker Daemon Not Running
If you see `failed to connect to the docker API`:
- Ensure Docker Desktop is running
- On Windows, check `Services` and restart Docker service if needed
- Restart Docker and retry: `docker ps`

### Image Build Failures
- Verify Dockerfile path is correct relative to build context
- Check for typos in `docker build` command
- Ensure base image is accessible: `docker pull <base-image>`

### ACR Push Failures
- Confirm ACR login: `az acr login --name <acr-name>`
- Check service principal has `AcrPush` role on ACR
- Verify image URI format: `<registry>.azurecr.io/<repo>:<tag>`

## Image Pull Failures in AKS

### ImagePullBackOff Error

**Symptom:** Pods show `ImagePullBackOff` status.

**Root causes:**

1. **Image doesn't exist in ACR**
   ```bash
   # Verify image was pushed
   az acr repository list --name <acr-name>
   az acr repository show-tags --name <acr-name> --repository <repo-name>
   ```

2. **AKS lacks pull permission**
   ```bash
   # Verify AKS kubelet identity has AcrPull role
   az role assignment list --scope /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.ContainerRegistry/registries/<acr-name> --role AcrPull
   ```

3. **Container port mismatch**
   - NGINX listens on port `80`
   - Ensure deployment spec has `containerPort: 80`

### Fix:

```bash
# Debug pod
kubectl describe pod <pod-name> -n production

# Check events
kubectl get events -n production --sort-by='.lastTimestamp'

# Verify image exists
az acr repository show --name <acr-name> --repository azuredevopsproject --image <image-tag>
```

## Terraform Issues

### Backend Lock Timeout

**Symptom:** `Error: Error acquiring the lease for state lock`

**Cause:** Another `terraform` operation is holding the state lock.

**Fix:**
```bash
# List locks
az storage blob lease list --account-name <storage-acct> --container-name tfstate

# Force unlock (use with caution!)
terraform force-unlock <lock-id>
```

### Provider Authentication Failures

```bash
# Verify Azure CLI authentication
az account show

# If needed, re-login
az login --subscription <subscription-id>

# Check Terraform provider logs
export TF_LOG=DEBUG
terraform apply
```

### Plan Drift

If `terraform plan` shows unexpected changes:

```bash
# Refresh state
terraform refresh

# Plan again
terraform plan
```

## Kubernetes Deployment Issues

### Rollout Timeout

**Symptom:** `error: timed out waiting for the condition`

**Causes:**
- Image pull backoff (see above)
- Pod readiness probe failures
- Insufficient cluster resources

**Fix:**
```bash
# Check pod status
kubectl get pods -n production

# View pod events
kubectl describe pod <pod-name> -n production

# Check logs
kubectl logs <pod-name> -n production

# Increase rollout timeout in deployment
kubectl rollout status deployment/azuredevopsproject -n production --timeout=600s

# Manually check service
kubectl get svc azuredevopsproject-svc -n production -o wide
```

### Service LoadBalancer Not Getting External IP

**Symptom:** `EXTERNAL-IP` shows `<pending>`.

**Causes:**
- LoadBalancer provisioning in progress (wait a few seconds)
- Cluster quota exceeded
- Network policy blocking egress

**Fix:**
```bash
# Check service status
kubectl get svc azuredevopsproject-svc -n production -o wide

# Check for events
kubectl describe svc azuredevopsproject-svc -n production

# If stuck, check node pool resources
kubectl top nodes

# If quota exceeded, delete and recreate service
kubectl delete svc azuredevopsproject-svc -n production
kubectl apply -f k8s/service.rendered.yaml
```

## Azure DevOps Pipeline Issues

### Service Connection Not Found

**Error:** `The specified resource could not be found.`

**Fix:**
- Confirm service connection name in pipeline matches Project Settings
- Update `prod-shared-config` variable group with correct connection name
- Verify service principal has sufficient permissions

### Variable Group Not Resolved

**Error:** `Variable 'xyz' is not defined.`

**Fix:**
- Ensure variable group `prod-shared-config` exists in Library
- Re-run pipeline after updating variable group
- Check for typos in variable names (case-sensitive)

### Terraform State Not Found

**Error:** `Error reading Terraform configuration in 'infra/terraform'`

**Fix:**
- Verify backend resource group, storage account, and container exist
- Confirm `tfStateResourceGroup`, `tfStateStorageAccount`, `tfStateContainer`, `tfStateKey` variables are set
- Test locally: `terraform init -backend-config=...`

## General Debugging Steps

1. **Enable verbose logging:**
   ```bash
   # Terraform
   export TF_LOG=DEBUG
   
   # Azure CLI
   export DEBUG=*
   ```

2. **Check resource group contents:**
   ```bash
   az resource list --resource-group <rg-name> --output table
   ```

3. **Validate permissions:**
   ```bash
   az role assignment list --assignee <service-principal-id> --output table
   ```

4. **Clean up test resources:**
   ```bash
   # Delete resource group (careful!)
   az group delete --name <rg-name> --yes --no-wait
   ```
