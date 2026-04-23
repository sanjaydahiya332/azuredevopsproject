param(
    [Parameter(Mandatory = $true)]
    [string]$OrganizationUrl,

    [Parameter(Mandatory = $true)]
    [string]$ProjectName,

    [Parameter(Mandatory = $false)]
    [string]$PipelineName = "azuredevopsproject-cicd",

    [Parameter(Mandatory = $false)]
    [string]$RepositoryName = "sanjaydahiya332/azuredevopsproject",

    [Parameter(Mandatory = $false)]
    [string]$Branch = "main",

    [Parameter(Mandatory = $false)]
    [switch]$RunAfterCreate
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

Write-Host "Validating Azure CLI..."
az account show --query "{subscription:id,user:user.name}" -o table | Out-Null

Write-Host "Ensuring azure-devops extension is installed..."
$ext = az extension show --name azure-devops --query name -o tsv 2>$null
if (-not $ext) {
    az extension add --name azure-devops --yes | Out-Null
}

Write-Host "Configuring Azure DevOps defaults..."
az devops configure --defaults organization=$OrganizationUrl project=$ProjectName | Out-Null

Write-Host "Creating or updating pipeline: $PipelineName"
$existingId = az pipelines list --organization $OrganizationUrl --project $ProjectName --query "[?name=='$PipelineName'].id | [0]" -o tsv

if ($existingId) {
    Write-Host "Pipeline already exists (id=$existingId). Updating YAML path and branch settings..."
    az pipelines update `
        --id $existingId `
        --organization $OrganizationUrl `
        --project $ProjectName `
        --name $PipelineName `
        --branch $Branch `
        --yml-path azure-pipelines.yml | Out-Null
    $pipelineId = $existingId
}
else {
    $pipelineId = az pipelines create `
        --name $PipelineName `
        --repository $RepositoryName `
        --repository-type github `
        --branch $Branch `
        --yml-path azure-pipelines.yml `
        --skip-first-run true `
        --organization $OrganizationUrl `
        --project $ProjectName `
        --query id -o tsv
}

if (-not $pipelineId) {
    throw "Pipeline creation/update did not return a pipeline id. Check Azure DevOps organization/project access and repository permissions."
}

Write-Host "Pipeline ready."
Write-Host "Pipeline Id: $pipelineId"

if ($RunAfterCreate) {
    Write-Host "Queueing pipeline run on branch '$Branch'..."
    $runId = az pipelines run `
        --id $pipelineId `
        --branch $Branch `
        --organization $OrganizationUrl `
        --project $ProjectName `
        --query id -o tsv

    if (-not $runId) {
        throw "Pipeline run was not queued successfully."
    }

    Write-Host "Run queued. Run Id: $runId"
}
