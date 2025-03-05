locals {
  region            = "us-east-1"
  project_name      = "nest"
  environment       = "dev"
  project_directory = "nest-app"
  domain_name       = "aosnotes77.com"
  record_name       = "www"
}

module "nest-app" {
  source = "../infrastructure"

  # Environment variables
  region            = local.region
  project_name      = local.project_name
  environment       = local.environment
  project_directory = local.project_directory

  # VPC variables
  vpc_cidr                     = "10.0.0.0/16"
  public_subnet_az1_cidr       = "10.0.0.0/24"
  public_subnet_az2_cidr       = "10.0.1.0/24"
  private_app_subnet_az1_cidr  = "10.0.2.0/24"
  private_app_subnet_az2_cidr  = "10.0.3.0/24"
  private_data_subnet_az1_cidr = "10.0.4.0/24"
  private_data_subnet_az2_cidr = "10.0.5.0/24"

  # Secrets Manager variables
  secret_name = "app-secrets"

  # RDS variables
  multi_az_deployment          = "false"
  database_instance_identifier = "app-db"
  database_instance_class      = "db.t3.micro"
  publicly_accessible          = "false"

  # ALB variables
  target_type        = "ip"
  health_check_path = "/index.php"

  # ACM variables
  domain_name       = local.domain_name
  alternative_names = "*.aosnotes77.com"

  # S3 variables
  env_file_bucket_name = "aosnote-ecs-env-variables"

  # ECS variables
  architecture = "X86_64"
  image_name   = "nest"
  image_tag    = "latest"

  # Data migrate EC2 instance 
  amazon_linux_ami_id = "ami-051f7e7f6c2f40dc1"
  ec2_instance_type   = "t2.micro"

  # Route-53 variables
  record_name = local.record_name
}