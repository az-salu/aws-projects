# Source the variables file
. (Join-Path $PSScriptRoot "variables.ps1")

# Verify AWS CLI configuration and credentials
Write-Host "Verifying AWS credentials..." -ForegroundColor Yellow
aws sts get-caller-identity
Check-CommandStatus "Failed to verify AWS credentials"

# Update kubeconfig
Write-Host "Updating kubeconfig..." -ForegroundColor Yellow
aws eks update-kubeconfig `
    --name $CLUSTER_NAME `
    --region $REGION
Check-CommandStatus "Failed to update kubeconfig"

# Apply aws-auth patch
Write-Host "Applying aws-auth ConfigMap..." -ForegroundColor Yellow
kubectl apply -f $AUTH_CONFIG_FILE_NAME
Check-CommandStatus "Failed to apply aws-auth ConfigMap"

# Apply Kubernetes resources
Write-Host "Applying Secret Provider Class..." -ForegroundColor Yellow
kubectl apply -f $SECRET_PROVIDER_CLASS_FILE_NAME
Check-CommandStatus "Failed to apply Secret Provider Class"

Write-Host "Applying Deployment..." -ForegroundColor Yellow
kubectl apply -f $DEPLOYMENT_FILE_NAME
Check-CommandStatus "Failed to apply Deployment"

Write-Host "Applying Service..." -ForegroundColor Yellow
kubectl apply -f $SERVICE_FILE_NAME
Check-CommandStatus "Failed to apply Service"

# Verify deployments
Write-Host "Verifying deployments..." -ForegroundColor Yellow
kubectl get pods -n $NAMESPACE
kubectl get services -n $NAMESPACE

Write-Host "Deployment complete! Please check the status of your pods and services." -ForegroundColor Yellow