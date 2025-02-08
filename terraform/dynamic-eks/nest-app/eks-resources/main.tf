# Data source to fetch outputs from the EKS cluster state
data "terraform_remote_state" "cluster" {
  backend = "s3"  # Specify S3 as the backend type
  
  config = {
    bucket  = "aosnote-terraform-remote-state"  # S3 bucket storing the cluster's terraform state
    key     = "nest-app/eks-cluster/terraform.tfstate"  # Path to the cluster's state file in the bucket
    region  = "us-east-1"  # AWS region where the S3 bucket is located
    profile = "cloud-projects"  # AWS credentials profile to use for accessing the state
  }
}

# Local variables used to store values that are used multiple times in the configuration file.
locals {
  account_id        = "651783246143"
  region            = "us-east-1"
  project_name      = "nest"
  environment       = "dev"
  secret_name       = "app-secrets"
  secret_suffix     = "ATCH9v"
}

# Create Kubernetes resources in the EKS cluster
module "eks_resources" {
  source = "../../infrastructure/eks-resources"

  providers = {
    kubernetes = kubernetes
    helm       = helm
    aws        = aws
  }

  # Environment variables
  account_id   = local.account_id
  region       = local.region
  project_name = local.project_name
  environment  = local.environment

  # Config map configuration
  eks_worker_node_role_arn = data.terraform_remote_state.cluster.outputs.eks_worker_node_role_arn
  admin_username = "labi"

  # OIDC provider configuration
  eks_cluster_oidc_issuer_url = data.terraform_remote_state.cluster.outputs.eks_cluster_oidc_issuer_url

  # Secret provider configuration
  secret_name   = local.secret_name
  secret_suffix = local.secret_suffix
}
