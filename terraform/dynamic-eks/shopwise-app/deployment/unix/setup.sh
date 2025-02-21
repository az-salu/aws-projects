#!/bin/bash

# Source the variables file
source "$(dirname "$0")/variables.sh"

# Verify AWS CLI configuration and credentials
echo -e "${YELLOW}Verifying AWS credentials...${NC}"
aws sts get-caller-identity
check_command "Failed to verify AWS credentials"

# Update kubeconfig 
echo -e "${YELLOW}Updating kubeconfig...${NC}"
aws eks update-kubeconfig \
    --name $CLUSTER_NAME \
    --region $REGION
check_command "Failed to update kubeconfig"

# Verify cluster access
echo -e "${YELLOW}Verifying cluster access...${NC}"
kubectl get nodes
check_command "Failed to access cluster nodes"

# Create namespace if it doesn't exist
echo -e "${YELLOW}Creating namespace $NAMESPACE if it doesn't exist...${NC}"
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Set the namespace for the current context
echo -e "${YELLOW}Setting default namespace...${NC}"
kubectl config set-context --current --namespace=$NAMESPACE
check_command "Failed to set namespace"

# Add Helm repository and update
echo -e "${YELLOW}Setting up Helm repository...${NC}"
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm repo update
check_command "Failed to setup Helm repository"

# Install CSI driver
echo -e "${YELLOW}Installing Secrets Store CSI Driver...${NC}"
helm install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver \
    --namespace kube-system \
    --set syncSecret.enabled=true \
    --set enableSecretRotation=true
check_command "Failed to install CSI driver"

# Verify CSI driver pods
echo -e "${YELLOW}Verifying CSI driver pods...${NC}"
kubectl --namespace=kube-system wait --for=condition=ready pod -l "app=secrets-store-csi-driver" --timeout=90s
check_command "CSI driver pods not ready"

# Install AWS provider
echo -e "${YELLOW}Installing AWS provider...${NC}"
kubectl apply -f https://raw.githubusercontent.com/aws/secrets-store-csi-driver-provider-aws/main/deployment/aws-provider-installer.yaml
check_command "Failed to install AWS provider"

# Setup OIDC provider
echo -e "${YELLOW}Setting up OIDC provider...${NC}"
eksctl utils associate-iam-oidc-provider --region=$REGION --cluster=$CLUSTER_NAME --approve
check_command "Failed to setup OIDC provider"

# Delete existing service account and its CloudFormation stack
echo -e "${YELLOW}Deleting existing service account and CloudFormation stack...${NC}"
STACK_NAME="eksctl-${CLUSTER_NAME}-addon-iamserviceaccount-${NAMESPACE}-${SERVICE_ACCOUNT_NAME}"

# Delete the Kubernetes service account
kubectl delete serviceaccount $SERVICE_ACCOUNT_NAME -n $NAMESPACE --ignore-not-found

# Delete the CloudFormation stack if it exists
aws cloudformation delete-stack --stack-name $STACK_NAME --region $REGION
aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME --region $REGION

# Create service account
echo -e "${YELLOW}Creating service account...${NC}"
eksctl create iamserviceaccount \
    --name $SERVICE_ACCOUNT_NAME \
    --namespace $NAMESPACE \
    --region $REGION \
    --cluster $CLUSTER_NAME \
    --attach-policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/$SECRET_MANAGER_ACCESS_POLICY_NAME" \
    --approve

# Verify service account creation
echo -e "${YELLOW}Verifying service account...${NC}"
kubectl get serviceaccount $SERVICE_ACCOUNT_NAME -n $NAMESPACE
check_command "Failed to verify service account creation"

echo -e "${YELLOW}Setup complete! You can now run the deployment script.${NC}"