locals {
  account_id        = "651783246143"
  region            = "us-east-1"
  project_name      = "nest"
  environment       = "dev"
  project_directory = "nest-app"
}

module "nest-app" {
  source = "../infrastructure"

  # environment variables
  account_id        = local.account_id
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
  secret_name   = "app-secrets"
  secret_suffix = "ATCH9v"

  # rds variables
  multi_az_deployment          = "false"
  database_instance_identifier = "app-db"
  database_instance_class      = "db.t3.micro"
  publicly_accessible          = "false"

  # eks variables
  public_access_cidrs = ["72.83.211.170/32"]
  admin_username      = "azeez"

  # data migrate ec2 instance variables
  amazon_linux_ami_id = "ami-051f7e7f6c2f40dc1"
  ec2_instance_type   = "t2.micro"
}
