# Local variables used to store values that are used multiple times in the configuration file.
locals {
  account_id        = "651783246143"
  region            = "us-east-1"
  project_name      = "nest"
  environment       = "dev"
  project_directory = "nest-app"
  secret_name       = "app-secrets"
  secret_suffix     = "ATCH9v"
}

# Create an EKS cluster and Worker Nodes
module "eks_cluster" {
  source = "../infrastructure/eks-cluster"

  # Environment variables
  account_id        = local.account_id
  region            = local.region
  project_name      = local.project_name
  environment       = local.environment
  project_directory = local.project_directory

  # VPC configuration
  vpc_cidr                     = "10.0.0.0/16"
  public_subnet_az1_cidr       = "10.0.0.0/24"
  public_subnet_az2_cidr       = "10.0.1.0/24"
  private_app_subnet_az1_cidr  = "10.0.2.0/24"
  private_app_subnet_az2_cidr  = "10.0.3.0/24"
  private_data_subnet_az1_cidr = "10.0.4.0/24"
  private_data_subnet_az2_cidr = "10.0.5.0/24"

  # Secrets Manager configuration
  secret_name   = local.secret_name
  secret_suffix = local.secret_suffix

  # RDS configuration
  multi_az_deployment          = "false"
  database_instance_identifier = "app-db"
  database_instance_class      = "db.t3.micro"
  publicly_accessible          = "false"

  # EKS configuration
  eks_cluster_version = "1.32"
  public_access_cidrs = ["72.83.211.170/32"]

  # Data migration EC2 instance configuration
  amazon_linux_ami_id = "ami-051f7e7f6c2f40dc1"
  ec2_instance_type   = "t2.micro"
}

# # Create Kubernetes resources in the EKS cluster
# module "eks_resources" {
#   source = "../infrastructure/eks-resources"

#   providers = {
#     kubernetes = kubernetes
#     helm       = helm
#   }

#   # Environment variables
#   account_id   = local.account_id
#   region       = local.region
#   project_name = local.project_name
#   environment  = local.environment

#   # Config map configuration
#   eks_worker_node_role_arn = module.eks_cluster.eks_worker_node_role_arn
#   admin_username = "azeez"

#   # # OIDC provider configuration
#   # eks_cluster_oidc_issuer_url = module.eks_cluster.eks_cluster_oidc_issuer_url

#   # # Secret provider configuration
#   # secret_name   = local.secret_name
#   # secret_suffix = local.secret_suffix
# }


# # Output the EKS cluster name
# output "eks_cluster_name" {
#   value = module.eks_cluster.eks_cluster_name
# }

# # Output the EKS cluster endpoint
# output "eks_cluster_endpoint" {
#   value = module.eks_cluster.eks_cluster_endpoint
# }

# # Output the EKS cluster CA certificate
# output "eks_cluster_ca_certificate" {
#   value = module.eks_cluster.eks_cluster_ca_certificate 
# }

# # Output the OIDC issuer URL for the EKS cluster
# output "eks_cluster_oidc_issuer_url" {
#   value = module.eks_cluster.eks_cluster_oidc_issuer_url
# }