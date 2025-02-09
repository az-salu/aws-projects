# Define variables
$APP_NAME = "nest"
$ENVIRONMENT = "dev"
$CLUSTER_NAME = "$APP_NAME-$ENVIRONMENT-eks-cluster"
$SECRET_MANAGER_ACCESS_POLICY_NAME = "$APP_NAME-$ENVIRONMENT-eks-secrets-policy"
$SERVICE_ACCOUNT_NAME = "$APP_NAME-service-account"

# Auth ConfigMap variables
$AUTH_CONFIG_FILE_NAME = "aws-auth-cm.yaml"
$IAM_USERNAME = "labi"

# Secret Provider Class variables
$SECRET_PROVIDER_CLASS_FILE_NAME = "secret-provider-class.yaml"
$SECRET_NAME = "app-secrets"
$SECRET_SUFFIX = "ATCH9v"
$SECRET_ALIAS = "$APP_NAME-$ENVIRONMENT-eks-secrets"

# Deployment variables
$DEPLOYMENT_FILE_NAME = "deployment.yaml"
$NAMESPACE = "$APP_NAME-$ENVIRONMENT-eks-namespace"
$REPLICAS = "1"
$APP_SECRETS = $SECRET_ALIAS
$AWS_ACCOUNT_ID = "651783246143"
$REGION = "us-east-1"
$ECR_REPO_NAME = $APP_NAME 
$IMAGE_TAG = "latest"
$PORT = "80"

# Service variables
$SERVICE_FILE_NAME = "service.yaml"
$LB_INTERNAL = "false"
$CROSS_ZONE_ENABLED = "true"


# Function to check command status
function Check-CommandStatus {
    param(
        [string]$ErrorMessage
    )
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: $ErrorMessage" -ForegroundColor Red
        exit 1
    }
}

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