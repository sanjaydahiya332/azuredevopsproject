# Azure DevOps CI/CD Setup Guide (GitHub -> ACR -> AKS)

This repository now includes:

- `azure-pipelines.yml` for CI/CD
- `infra/terraform/*` for provisioning Azure infrastructure
- `k8s/*` for Kubernetes deployment
- `pipelines/templates/stages/deploy-aks-stage.yml` as reusable deployment stage template

## 1. Prerequisites

- Azure subscription with permissions to create:
  - Resource Groups
  - Azure Container Registry (ACR)
  - Azure Kubernetes Service (AKS)
  - Role assignments (`AcrPull`)
- Azure DevOps project
- GitHub repository containing your app source + Dockerfile
- Azure Key Vault (recommended) with secret: `appSecret`

## 2. Azure DevOps Service Connections

Create these service connections in Azure DevOps Project Settings:

1. `github-service-connection`
- Type: GitHub
- Scope: Repository `sanjaydahiya332/azuredevopsproject`

2. `sc-azure-prod` (or your chosen name)
- Type: Azure Resource Manager
- Authentication: Service principal (automatic or manual)
- Scope: Subscription (or resource group if constrained)

The service principal must have at least:

- `Contributor` on target scope
- `User Access Administrator` on target scope (for role assignment to grant AKS pull from ACR)

## 3. Variable Group

Create variable group: `prod-shared-config` and add:

- `azureServiceConnection` = `sc-azure-prod`
- `appName` = `azuredevopsproject`
- `subscriptionId` = your subscription GUID
- `location` = e.g. `centralindia`
- `environment` = `prod`
- `projectName` = `azuredevopsproject`
- `projectName` = logical project name used for tags and AKS DNS prefix (for example, `myapp`)
- `resourceGroupName` = e.g. `rg-myapp-prod`
- `acrName` = globally unique ACR name, e.g. `acrmyappprod01`
- `aksName` = e.g. `aks-myapp-prod`
- `aksKubernetesVersion` = e.g. `1.34.4` (supports non-LTS on Free tier; use `1.30.x+` for LTS if Premium)
- `aksNodeCount` = `1` (minimum; scale up after successful provisioning)
- `aksNodeVmSize` = `Standard_F2as_v6` (adjust based on region quota availability; see [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for quota issues)
- `keyVaultName` = existing Key Vault name
- `tfStateResourceGroup` = e.g. `rg-tfstate-shared-prod`
- `tfStateStorageAccount` = globally unique storage account, e.g. `sttfstateprod001`
- `tfStateContainer` = e.g. `tfstate`
- `tfStateKey` = e.g. `myapp-prod.tfstate`

Mark sensitive values as secrets where applicable.

**Note:** Defaults in this guide are tested in `centralindia` region. If you deploy to another region, verify VM size and Kubernetes version availability before running the pipeline.

## 4. Key Vault Access

- In Key Vault, create secret: `appSecret`
- Allow Azure DevOps service principal to `Get`/`List` Key Vault secrets
- Ensure the same Azure service connection is used in `AzureKeyVault@2`

## 5. Terraform Inputs

The pipeline passes variables directly to Terraform.

For local testing, copy and update:

- `infra/terraform/terraform.tfvars.example` -> `infra/terraform/terraform.tfvars`

## 6. Pipeline Behavior

Stage 1: `ProvisionInfra`
- Checks out GitHub repo
- Creates/ensures Terraform backend resources (RG, Storage Account, Container)
- Runs `terraform init` against remote `azurerm` backend, then `fmt`, `validate`, `plan`, `apply`
- Provisions RG, ACR, AKS
- Assigns `AcrPull` role to AKS kubelet identity
- Exports outputs for downstream stages

Stage 2: `BuildAndPush`
- Builds Docker image from `Dockerfile`
- Tags as `<BuildId>-<shortCommitSha>`
- Pushes to ACR

Stage 3: `SecurityScan`
- Installs and runs Trivy scan against pushed image
- Fails pipeline on `HIGH`/`CRITICAL` vulnerabilities

Stage 4: `DeployDev`
- Deploys image to AKS namespace `dev`

Stage 5: `DeployProd`
- Promotes deployment to namespace `production` after successful dev deployment

Both deploy stages:
- Get AKS credentials with `az aks get-credentials`
- Render manifests with runtime image URI and namespace
- Perform rollout verification with `kubectl rollout status`
- Expose app via `LoadBalancer`

## 7. Rolling Updates and HA Settings

`k8s/deployment.yaml` includes:

- `replicas: 3`
- Rolling strategy (`maxUnavailable: 0`, `maxSurge: 1`)
- Readiness and liveness probes
- CPU and memory requests/limits

`k8s/deployment.yaml` and `k8s/service.yaml` are template-friendly and rendered with pipeline values for:

- image URI
- namespace (`dev` or `production`)

## 8. First Run Checklist

1. Commit these files to your repository that Azure DevOps pipeline reads.
2. Confirm service connection names and variable group values.
3. Create Azure DevOps pipeline using existing YAML (`azure-pipelines.yml`).
4. Run pipeline manually once.
5. Validate:
- ACR exists and image is pushed
- AKS cluster is healthy
- Dev and production deployments are available
- Service external IP is assigned for each namespace service

Optional automation (Azure DevOps CLI):

```powershell
pwsh ./scripts/create-azdo-pipeline.ps1 \
  -OrganizationUrl "https://dev.azure.com/<your-org>" \
  -ProjectName "<your-project>" \
  -PipelineName "azuredevopsproject-cicd" \
  -RepositoryName "sanjaydahiya332/azuredevopsproject" \
  -Branch "main" \
  -RunAfterCreate
```

This script creates the YAML pipeline (or updates it if it already exists), and can optionally queue a run.

## 9. Operational Hardening Recommendations

- Configure Terraform remote state (Azure Storage backend + state locking) ✓ Implemented
- Use AKS autoscaling and multiple node pools for production workloads
- Enable Azure Policy for AKS and Defender for Cloud
- Keep Trivy DB cache between runs using pipeline caching for faster scans
- Add gated approvals for production environment in Azure DevOps

## 10. Common Issues and Solutions

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for:
- Region and quota constraints
- Docker and container issues
- Image pull failures in AKS
- Terraform backend issues
- Kubernetes deployment issues
- Azure DevOps pipeline errors
