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

# Null resource to run the deployment script after EKS cluster is ready
resource "null_resource" "deploy_to_eks" {
  triggers = {
    cluster_endpoint = module.eks_cluster.eks_cluster_endpoint
    script_hash     = filesha256("${path.module}/deployment/deployment.sh")
  }

  provisioner "local-exec" {
    working_dir = "${path.module}/deployment"
    interpreter = ["/bin/bash", "-c"]
    
    command = <<-EOT
      # Wait for the EKS cluster to be fully ready
      echo "Waiting for EKS cluster to be ready..."
      aws eks wait cluster-active --name nest-dev-eks-cluster --region ${local.region}
      
      # Execute the deployment script
      ./deployment.sh

      # Wait for the load balancer to be created and active
      echo "Waiting for Load Balancer to be ready..."
      sleep 60  # Give some time for the NLB to be created
    EOT
  }

  depends_on = [
    module.eks_cluster
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
    "kubernetes.io/service-name" = "nest-dev-eks-namespace/nest-dev-eks-service"
  }

  depends_on = [
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
    zone_id               = data.aws_lb.nlb.zone_id
    evaluate_target_health = true
  }

  depends_on = [
    data.aws_lb.nlb
  ]
}

# Output the DNS details
output "load_balancer_dns" {
  value = data.aws_lb.nlb.dns_name
}

# Website URL
output "website_url" {
  value = join("", ["https://", aws_route53_record.route53_record.name, ".", data.aws_route53_zone.route53_zone.name])
}
