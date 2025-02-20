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

# Apply aws-auth patch
echo -e "${YELLOW}Applying aws-auth ConfigMap...${NC}"
kubectl apply -f $AUTH_CONFIG_FILE_NAME
check_command "Failed to apply aws-auth ConfigMap"

# Apply Kubernetes resources
echo -e "${YELLOW}Applying Secret Provider Class...${NC}"
kubectl apply -f $SECRET_PROVIDER_CLASS_FILE_NAME
check_command "Failed to apply Secret Provider Class"

echo -e "${YELLOW}Applying Deployment...${NC}"
kubectl apply -f $DEPLOYMENT_FILE_NAME
check_command "Failed to apply Deployment"

echo -e "${YELLOW}Applying Service...${NC}"
kubectl apply -f $SERVICE_FILE_NAME
check_command "Failed to apply Service"

# Verify deployments
echo -e "${YELLOW}Verifying deployments...${NC}"
kubectl get pods -n $NAMESPACE
kubectl get services -n $NAMESPACE

echo -e "${YELLOW}Deployment complete! Please check the status of your pods and services.${NC}"