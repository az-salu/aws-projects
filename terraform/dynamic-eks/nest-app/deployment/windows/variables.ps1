# Define common variables
$CLUSTER_NAME = "nest-dev-eks-cluster"
$NAMESPACE = "nest-dev-eks-namespace"
$REGION = "us-east-1"
$AWS_ACCOUNT_ID = "651783246143"

# File names with extension
$SECRET_PROVIDER_CLASS_FILE_NAME = "secret-provider-class.yaml"
$DEPLOYMENT_FILE_NAME = "deployment.yaml"
$SERVICE_FILE_NAME = "service.yaml"
$AUTH_CONFIG_FILE_NAME = "aws-auth-patch.yaml"

# Service Account variables
$SERVICE_ACCOUNT_NAME = "nest-dev-eks-service-account"
$SECRET_MANAGER_ACCESS_POLICY_NAME = "secrets-manager-access-policy"

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
