# Define colors
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m' # No Color

# Define common variables
CLUSTER_NAME="nest-dev-eks-cluster"
NAMESPACE="nest-dev-eks-namespace"
REGION="us-east-1"
AWS_ACCOUNT_ID="651783246143"

# File names with extension
SECRET_PROVIDER_CLASS_FILE_NAME="secret-provider-class.yaml"
DEPLOYMENT_FILE_NAME="deployment.yaml"
SERVICE_FILE_NAME="service.yaml"
AUTH_CONFIG_FILE_NAME="aws-auth-patch.yaml"

# Service Account variables
SERVICE_ACCOUNT_NAME="nest-dev-eks-service-account"
SECRET_MANAGER_ACCESS_POLICY_NAME="secrets-manager-access-policy"

# Function to check command status
check_command() {
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: $1${NC}"
        exit 1
    fi
}
