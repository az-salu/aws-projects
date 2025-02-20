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

# Verify cluster access
Write-Host "Verifying cluster access..." -ForegroundColor Yellow
kubectl get nodes
Check-CommandStatus "Failed to access cluster nodes"

# Create namespace if it doesn't exist
Write-Host "Creating namespace $NAMESPACE if it doesn't exist..." -ForegroundColor Yellow
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Set the namespace for the current context
Write-Host "Setting default namespace..." -ForegroundColor Yellow
kubectl config set-context --current --namespace=$NAMESPACE
Check-CommandStatus "Failed to set namespace"

# Add Helm repository and update
Write-Host "Setting up Helm repository..." -ForegroundColor Yellow
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm repo update
Check-CommandStatus "Failed to setup Helm repository"

# Install CSI driver
Write-Host "Installing Secrets Store CSI Driver..." -ForegroundColor Yellow
helm install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver `
    --namespace kube-system `
    --set syncSecret.enabled=true `
    --set enableSecretRotation=true
Check-CommandStatus "Failed to install CSI driver"

# Verify CSI driver pods
Write-Host "Verifying CSI driver pods..." -ForegroundColor Yellow
kubectl --namespace=kube-system wait --for=condition=ready pod -l "app=secrets-store-csi-driver" --timeout=90s
Check-CommandStatus "CSI driver pods not ready"

# Install AWS provider
Write-Host "Installing AWS provider..." -ForegroundColor Yellow
kubectl apply -f https://raw.githubusercontent.com/aws/secrets-store-csi-driver-provider-aws/main/deployment/aws-provider-installer.yaml
Check-CommandStatus "Failed to install AWS provider"

# Setup OIDC provider
Write-Host "Setting up OIDC provider..." -ForegroundColor Yellow
eksctl utils associate-iam-oidc-provider --region=$REGION --cluster=$CLUSTER_NAME --approve
Check-CommandStatus "Failed to setup OIDC provider"

# Delete existing service account and its CloudFormation stack
Write-Host "Deleting existing service account and CloudFormation stack..." -ForegroundColor Yellow
$STACK_NAME = "eksctl-${CLUSTER_NAME}-addon-iamserviceaccount-${NAMESPACE}-${SERVICE_ACCOUNT_NAME}"

# Delete the Kubernetes service account
kubectl delete serviceaccount $SERVICE_ACCOUNT_NAME -n $NAMESPACE --ignore-not-found

# Delete the CloudFormation stack if it exists
aws cloudformation delete-stack --stack-name $STACK_NAME --region $REGION
aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME --region $REGION

# Create service account
Write-Host "Creating service account..." -ForegroundColor Yellow
eksctl create iamserviceaccount `
    --name $SERVICE_ACCOUNT_NAME `
    --namespace $NAMESPACE `
    --region $REGION `
    --cluster $CLUSTER_NAME `
    --attach-policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${SECRET_MANAGER_ACCESS_POLICY_NAME}" `
    --approve

# Verify service account creation
Write-Host "Verifying service account..." -ForegroundColor Yellow
kubectl get serviceaccount $SERVICE_ACCOUNT_NAME -n $NAMESPACE
Check-CommandStatus "Failed to verify service account creation"

Write-Host "Setup complete! You can now run the deployment script." -ForegroundColor Yellow