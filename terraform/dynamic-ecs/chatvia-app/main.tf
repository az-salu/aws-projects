locals {
  region            = "us-east-1"
  project_name      = "chatvia"
  environment       = "dev"
  project_directory = "chatvia-app"
  domain_name       = "aosnotes77.com"
  record_name       = "www"
}

module "chatvia-app" {
  source = "../infrastructure"

  # environment variables
  region            = local.region
  project_name      = local.project_name
  environment       = local.environment
  project_directory = local.project_directory

  # vpc variables
  vpc_cidr                     = "10.0.0.0/16"
  public_subnet_az1_cidr       = "10.0.0.0/24"
  public_subnet_az2_cidr       = "10.0.1.0/24"
  private_app_subnet_az1_cidr  = "10.0.2.0/24"
  private_app_subnet_az2_cidr  = "10.0.3.0/24"
  private_data_subnet_az1_cidr = "10.0.4.0/24"
  private_data_subnet_az2_cidr = "10.0.5.0/24"

  # secrets manager variables
  secrets_manager_secret_name = "app-secrets"

  # rds variables
  multi_az_deployment          = "false"
  database_instance_identifier = "app-db"
  database_instance_class      = "db.t3.micro"
  publicly_accessible          = "false"

  # alb variables
  health_check_path = "/"

  # acm variables
  domain_name       = local.domain_name
  alternative_names = "*.aosnotes77.com"

  # s3 variables
  env_file_bucket_name = "aosnote-ecs-env-variables"

  # ecs variables
  architecture = "X86_64"
  image_name   = "chatvia"
  image_tag    = "latest"

  # data migrate ec2 instance 
  amazon_linux_ami_id = "ami-051f7e7f6c2f40dc1"
  ec2_instance_type   = "t2.micro"

  # route-53 variables
  record_name = local.record_name
}