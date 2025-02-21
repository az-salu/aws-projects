# Local variables used to store values that are used multiple times in the configuration file.
locals {
  account_id        = "651783246143"
  region            = "us-east-1"
  project_name      = "chatvia"
  environment       = "dev"
  project_directory = "chatvia-app"
  secret_name       = "app-secrets"
  secret_suffix     = "ATCH9v"

  setup_command_windows = <<-EOT
    Write-Host "Running initial setup..."
    .\windows\setup.ps1
  EOT

  setup_command_unix = <<-EOT
    echo "Running initial setup..."
    ./unix/setup.sh
  EOT

  deploy_command_windows = <<-EOT
    Write-Host "Waiting for EKS cluster to be ready..."
    aws eks wait cluster-active --name $env:CLUSTER_NAME --region $env:REGION
    .\windows\deployment.ps1
    Write-Host "Waiting for Load Balancer to be ready..."
    Start-Sleep -Seconds 60
  EOT

  deploy_command_unix = <<-EOT
    echo "Waiting for EKS cluster to be ready..."
    aws eks wait cluster-active --name $CLUSTER_NAME --region $REGION
    ./unix/deployment.sh
    echo "Waiting for Load Balancer to be ready..."
    sleep 60
  EOT

  cleanup_command_windows = <<-EOT
    Write-Host "Cleaning up Network Load Balancer..."
    kubectl delete service $env:SERVICE_NAME -n $env:NAMESPACE --ignore-not-found=true
    Write-Host "Waiting for Load Balancer to be deleted..."
    Start-Sleep -Seconds 30
  EOT

  cleanup_command_unix = <<-EOT
    echo "Cleaning up Network Load Balancer..."
    kubectl delete service $SERVICE_NAME -n $NAMESPACE --ignore-not-found=true
    echo "Waiting for Load Balancer to be deleted..."
    sleep 30
  EOT
}

# Create an EKS cluster and Worker Nodes
module "eks_cluster" {
  source = "../infrastructure"

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

# Setup resource that only runs when var.run_setup is true
resource "null_resource" "eks_setup" {
  count = var.run_setup ? 1 : 0

  triggers = {
    script_hash   = var.is_windows ? filesha256("${path.module}/deployment/windows/setup.ps1") : filesha256("${path.module}/deployment/unix/setup.sh")
    is_windows    = var.is_windows ? "true" : "false"
    setup_command = var.is_windows ? local.setup_command_windows : local.setup_command_unix
  }

  provisioner "local-exec" {
    working_dir = "${path.module}/deployment"
    interpreter = self.triggers.is_windows == "true" ? ["PowerShell", "-Command"] : ["/bin/bash", "-c"]
    command     = self.triggers.setup_command
  }

  depends_on = [
    module.eks_cluster
  ]
}

# Null resource to run the deployment script after EKS cluster is ready
resource "null_resource" "deploy_to_eks" {
  triggers = {
    cluster_endpoint = module.eks_cluster.eks_cluster_endpoint
    script_hash      = var.is_windows ? filesha256("${path.module}/deployment/windows/deployment.ps1") : filesha256("${path.module}/deployment/unix/deployment.sh")
    region           = local.region
    namespace        = "${local.project_name}-${local.environment}-eks-namespace"
    cluster_name     = "${local.project_name}-${local.environment}-eks-cluster"
    service_name     = "${local.project_name}-${local.environment}-eks-service"
    is_windows       = var.is_windows ? "true" : "false"
    deploy_command   = var.is_windows ? local.deploy_command_windows : local.deploy_command_unix
    cleanup_command  = var.is_windows ? local.cleanup_command_windows : local.cleanup_command_unix
  }

  # Deployment Provisioner
  provisioner "local-exec" {
    working_dir = "${path.module}/deployment"
    interpreter = self.triggers.is_windows == "true" ? ["PowerShell", "-Command"] : ["/bin/bash", "-c"]
    environment = {
      CLUSTER_NAME = self.triggers.cluster_name
      REGION       = self.triggers.region
    }
    command = self.triggers.deploy_command
  }

  # Cleanup Provisioner. Will delete the Service and the Network Load Balancer
  provisioner "local-exec" {
    when        = destroy
    working_dir = "${path.module}/deployment"
    interpreter = self.triggers.is_windows == "true" ? ["PowerShell", "-Command"] : ["/bin/bash", "-c"]
    environment = {
      NAMESPACE    = self.triggers.namespace
      SERVICE_NAME = self.triggers.service_name
    }
    command = self.triggers.cleanup_command
  }

  depends_on = [
    module.eks_cluster,
    null_resource.eks_setup
  ]
}

# Get the hosted zone ID
data "aws_route53_zone" "route53_zone" {
  name         = "aosnotes77.com"
  private_zone = false
}

# Get the NLB details - this will now wait for the deployment
data "aws_lb" "nlb" {
  tags = {
    "kubernetes.io/service-name" = "${local.project_name}-${local.environment}-eks-namespace/${local.project_name}-${local.environment}-eks-service"
  }

  depends_on = [
    null_resource.eks_setup,
    null_resource.deploy_to_eks
  ]
}

# Create the A record
resource "aws_route53_record" "route53_record" {
  zone_id = data.aws_route53_zone.route53_zone.zone_id
  name    = "www"
  type    = "A"

  alias {
    name                   = data.aws_lb.nlb.dns_name
    zone_id                = data.aws_lb.nlb.zone_id
    evaluate_target_health = true
  }

  depends_on = [
    data.aws_lb.nlb
  ]
}

# This resource will wait 30 seconds before completing the deployment
resource "time_sleep" "wait_after_record" {
  depends_on = [aws_route53_record.route53_record]

  create_duration = "30s"
}

# Output the DNS details
output "load_balancer_dns" {
  value = data.aws_lb.nlb.dns_name
}

# Website URL
output "website_url" {
  value = join("", ["https://", aws_route53_record.route53_record.name, ".", data.aws_route53_zone.route53_zone.name])
}
