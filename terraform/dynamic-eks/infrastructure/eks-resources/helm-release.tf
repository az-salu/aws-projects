# Define a local variable to detect the operating system
# This checks if the expanded home directory starts with "C", 
# which is common in Windows. It's a heuristic and may not work in all cases.
locals {
  is_windows = substr(pathexpand("~"), 0, 1) == "C"

  windows_command = <<-EOT
    # Create the charts directory if it doesn't exist (Windows)
    if (-not (Test-Path "charts")) {
       New-Item -ItemType Directory -Force -Path "charts"
    }
    # Add and update the Helm repository
    helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
    helm repo update
    # Pull the Helm chart and store it in the charts directory
    helm pull secrets-store-csi-driver/secrets-store-csi-driver --version ${var.csi_driver_version} --destination "charts"
  EOT

  linux_command = <<-EOF
    # Create the charts directory if it doesn't exist (Linux/MacOS)
    mkdir -p charts
    # Add and update the Helm repository
    helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
    helm repo update
    # Pull the Helm chart and store it in the charts directory
    helm pull secrets-store-csi-driver/secrets-store-csi-driver --version ${var.csi_driver_version} --destination charts
  EOF
}

# Download and prepare the Helm chart
# This resource is responsible for:
# 1. Creating a local directory for charts
# 2. Adding the Secrets Store CSI Driver Helm repository
# 3. Updating Helm repositories
# 4. Downloading the chart locally
# Commands are executed using PowerShell on Windows and Bash on Linux/MacOS
resource "null_resource" "download_chart" {
  provisioner "local-exec" {
    interpreter = local.is_windows ? ["PowerShell", "-Command"] : ["/bin/bash", "-c"]
    command     = local.is_windows ? local.windows_command : local.linux_command

    # Set working directory to ensure charts are created in the right place
    working_dir = path.root
  }
}

# Install the Secrets Store CSI Driver for Kubernetes
# This driver enables Kubernetes to mount multiple secrets, keys, and certs 
# stored in enterprise-grade external secrets stores into their pods as volumes
resource "helm_release" "secrets_store_csi_driver" {
  name             = "csi-secrets-store"
  chart            = "${path.root}/charts/secrets-store-csi-driver-${var.csi_driver_version}.tgz"
  namespace        = "kube-system"
  create_namespace = true
  force_update     = true # Forces resource update through delete/recreate if needed
  cleanup_on_fail  = true # Cleanup any created resources if the install fails

  # Ensure chart is downloaded before attempting installation
  depends_on = [
    null_resource.download_chart
  ]

  # Enable secret syncing to create k8s secrets
  # This allows the driver to create Kubernetes secrets from provider secrets
  set {
    name  = "syncSecret.enabled"
    value = "true"
  }

  # Enable automatic secret rotation
  # This ensures secrets are automatically updated when they change in the provider
  set {
    name  = "enableSecretRotation"
    value = "false"
  }
}

# AWS provider for Secrets Store CSI Driver
resource "helm_release" "secrets_store_csi_driver_provider_aws" {
  name       = "${var.project_name}-${var.environment}-eks-csi-aws-provider"
  repository = "https://aws.github.io/eks-charts"
  chart      = "csi-secrets-store-provider-aws" # Don't change this
  namespace  = "kube-system"

  depends_on = [
    helm_release.secrets_store_csi_driver
  ]
}
