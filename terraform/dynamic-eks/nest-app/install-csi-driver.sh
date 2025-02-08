#!/bin/bash

# Connect to EKS cluster
echo "Connecting to EKS cluster..."
aws eks update-kubeconfig --region us-east-1 --name nest-dev-eks-cluster

# Add Helm repositories
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm repo add aws-secrets-manager https://aws.github.io/secrets-store-csi-driver-provider-aws
helm repo update

# Install CSI Driver
helm install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver \
  --namespace kube-system \
  --set syncSecret.enabled=true

# Install AWS Provider
helm install secrets-provider aws-secrets-manager/secrets-store-csi-driver-provider-aws \
  --namespace kube-system

# Verify installations
echo "Checking CSI pods..."
kubectl get pods -n kube-system | grep csi

echo "Checking secrets provider pods..."
kubectl get pods -n kube-system | grep secrets-provider

echo "Verifying CRD installation..."
kubectl get crd | grep secretproviderclasses
