# Define variables
$CLUSTER_NAME = "nest-dev-eks-cluster"
$SECRET_MANAGER_ACCESS_POLICY_NAME = "secrets-manager-access-policy" # Must create policy first with secret manager access 
$NAMESPACE = "nest-app"
$REGION = "us-east-1"
$AWS_ACCOUNT_ID = "651783246143"
$SERVICE_ACCOUNT_NAME = "nest-app-service-account"
$SECRET_PROVIDER_CLASS_FILE_NAME = "secret-provider-class.yaml"
$DEPLOYMENT_FILE_NAME = "deployment.yaml"
$SERVICE_FILE_NAME = "service.yaml"
$AUTH_CONFIG_FILE_NAME = "aws-auth-patch.yaml"

# Function to check command status
function Check-CommandStatus {
    param(
        [string]$ErrorMessage
    )
    if (-not $?) {
        Write-Error "Error: $ErrorMessage"
        exit 1
    }
}

# Verify AWS CLI configuration and credentials
Write-Host "Verifying AWS credentials..."
aws sts get-caller-identity
Check-CommandStatus "Failed to verify AWS credentials"

# Update kubeconfig with additional parameters
Write-Host "Updating kubeconfig..."
aws eks update-kubeconfig `
    --name $CLUSTER_NAME `
    --region $REGION
Check-CommandStatus "Failed to update kubeconfig"

# Apply aws-auth patch
Write-Host "Applying aws-auth ConfigMap..."
kubectl apply -f $AUTH_CONFIG_FILE_NAME
Check-CommandStatus "Failed to apply aws-auth ConfigMap"

# Verify cluster access
Write-Host "Verifying cluster access..."
kubectl get nodes
Check-CommandStatus "Failed to access cluster nodes"

# Create namespace if it doesn't exist
Write-Host "Creating namespace $NAMESPACE if it doesn't exist..."
$namespaceYaml = kubectl create namespace $NAMESPACE --dry-run=client -o yaml
$namespaceYaml | kubectl apply -f -

# Set the namespace for the current context
Write-Host "Setting default namespace..."
kubectl config set-context --current --namespace=$NAMESPACE
Check-CommandStatus "Failed to set namespace"

# Add Helm repository and update
Write-Host "Setting up Helm repository..."
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm repo update
Check-CommandStatus "Failed to setup Helm repository"

# Install CSI driver
Write-Host "Installing Secrets Store CSI Driver..."
helm install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver `
    --namespace kube-system `
    --set syncSecret.enabled=true `
    --set enableSecretRotation=true
Check-CommandStatus "Failed to install CSI driver"

# Verify CSI driver pods
Write-Host "Verifying CSI driver pods..."
kubectl --namespace=kube-system wait --for=condition=ready pod -l "app=secrets-store-csi-driver" --timeout=90s
Check-CommandStatus "CSI driver pods not ready"

# Install AWS provider
Write-Host "Installing AWS provider..."
kubectl apply -f https://raw.githubusercontent.com/aws/secrets-store-csi-driver-provider-aws/main/deployment/aws-provider-installer.yaml
Check-CommandStatus "Failed to install AWS provider"

# Setup OIDC provider
Write-Host "Setting up OIDC provider..."
eksctl utils associate-iam-oidc-provider --region=$REGION --cluster=$CLUSTER_NAME --approve
Check-CommandStatus "Failed to setup OIDC provider"

# Delete existing service account and its CloudFormation stack
Write-Host "Deleting existing service account and CloudFormation stack..."
$STACK_NAME = "eksctl-${CLUSTER_NAME}-addon-iamserviceaccount-${NAMESPACE}-${SERVICE_ACCOUNT_NAME}"

# Delete the Kubernetes service account
kubectl delete serviceaccount $SERVICE_ACCOUNT_NAME -n $NAMESPACE --ignore-not-found

# Delete the CloudFormation stack if it exists
aws cloudformation delete-stack --stack-name $STACK_NAME --region $REGION
aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME --region $REGION

# Create service account
Write-Host "Creating service account..."
eksctl create iamserviceaccount `
   --name $SERVICE_ACCOUNT_NAME `
   --namespace $NAMESPACE `
   --region $REGION `
   --cluster $CLUSTER_NAME `
   --attach-policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/$SECRET_MANAGER_ACCESS_POLICY_NAME" `
   --approve

# Verify service account creation
Write-Host "Verifying service account..."
kubectl get serviceaccount $SERVICE_ACCOUNT_NAME -n $NAMESPACE
if (-not $?) {
   Write-Error "Failed to verify service account creation"
   exit 1
}

# Apply Kubernetes resources
Write-Host "Applying Secret Provider Class..."
kubectl apply -f $SECRET_PROVIDER_CLASS_FILE_NAME
Check-CommandStatus "Failed to apply Secret Provider Class"

Write-Host "Applying Deployment..."
kubectl apply -f $DEPLOYMENT_FILE_NAME
Check-CommandStatus "Failed to apply Deployment"

Write-Host "Applying Service..."
kubectl apply -f $SERVICE_FILE_NAME
Check-CommandStatus "Failed to apply Service"

# Verify deployments
Write-Host "Verifying deployments..."
kubectl get pods -n $NAMESPACE
kubectl get services -n $NAMESPACE

Write-Host "Deployment complete! Please check the status of your pods and services." -ForegroundColor Green