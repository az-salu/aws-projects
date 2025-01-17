locals {
  region       = "us-east-1"
  project_name = "shopwise"
  environment  = "dev"

  # secret_manager module
  secrets_manager_secret_name = "app-secrets"

  # rds module
  engine                       = "mysql"
  engine_version               = "8.0.39"
  multi_az_deployment          = "false"
  database_instance_identifier = "app-db"
  database_instance_class      = "db.t3.micro"

  # data_migrate_ec2 module
  amazon_linux_ami_id = "ami-051f7e7f6c2f40dc1"
  ec2_instance_type   = "t2.micro"
  project_directory   = "dynamic-ecs/shopwise-app"

  # ssl_cetificate module 
  domain_name       = "aosnotes77.com"
  alternative_names = "*.aosnotes77.com"

  # s3_bucket module
  env_file_bucket_name = "aosnote-ecs-env-files"
  env_file_name        = "shopwise.env"

  # ecs module
  container_image = "651783246143.dkr.ecr.us-east-1.amazonaws.com/shopwise:latest"

  # route_53 module
  record_name = "www"
}

# create vpc
module "vpc" {
  source                       = "../../modules/vpc"
  region                       = local.region
  project_name                 = local.project_name
  environment                  = local.environment
  vpc_cidr                     = "10.0.0.0/16"
  public_subnet_az1_cidr       = "10.0.0.0/24"
  public_subnet_az2_cidr       = "10.0.1.0/24"
  private_app_subnet_az1_cidr  = "10.0.2.0/24"
  private_app_subnet_az2_cidr  = "10.0.3.0/24"
  private_data_subnet_az1_cidr = "10.0.4.0/24"
  private_data_subnet_az2_cidr = "10.0.5.0/24"
}

# create nat gatways 
module "nat_gateway" {
  source                     = "../../modules/nat-gateway"
  project_name               = local.project_name
  environment                = local.environment
  public_subnet_az1_id       = module.vpc.public_subnet_az1_id
  internet_gateway           = module.vpc.internet_gateway
  public_subnet_az2_id       = module.vpc.public_subnet_az2_id
  vpc_id                     = module.vpc.vpc_id
  private_app_subnet_az1_id  = module.vpc.private_app_subnet_az1_id
  private_data_subnet_az1_id = module.vpc.private_data_subnet_az1_id
  private_app_subnet_az2_id  = module.vpc.private_app_subnet_az2_id
  private_data_subnet_az2_id = module.vpc.private_data_subnet_az2_id
}

# create security groups
module "security_group" {
  source       = "../../modules/security-groups/ecs-security-groups"
  project_name = local.project_name
  environment  = local.environment
  vpc_cidr     = module.vpc.vpc_cidr
  vpc_id       = module.vpc.vpc_id
}

# create the ec2 instance connect endpoint 
module "eice" {
  source                     = "../../modules/eice"
  project_name               = local.project_name
  environment                = local.environment
  private_data_subnet_az1_id = module.vpc.private_data_subnet_az1_id
  eice_security_group_id     = module.security_group.eice_security_group_id
}

# get secrets from secret manager
module "secret_manager" {
  source                      = "../../modules/secret-manager"
  secrets_manager_secret_name = local.secrets_manager_secret_name
}

# launch rds instance
module "rds" {
  source                       = "../../modules/rds"
  project_name                 = local.project_name
  environment                  = local.environment
  private_data_subnet_az1_id   = module.vpc.private_data_subnet_az1_id
  private_data_subnet_az2_id   = module.vpc.private_data_subnet_az2_id
  engine                       = local.engine
  engine_version               = local.engine_version
  multi_az_deployment          = local.multi_az_deployment
  database_instance_identifier = local.database_instance_identifier
  rds_db_username              = module.secret_manager.rds_db_username
  rds_db_password              = module.secret_manager.rds_db_password
  rds_db_name                  = module.secret_manager.rds_db_name
  database_instance_class      = local.database_instance_class
  allocated_storage            = 200
  database_security_group_id   = module.security_group.database_security_group_id
  availability_zone_1          = module.vpc.availability_zone_1
  skip_final_snapshot          = true
  publicly_accessible          = false
}

# create ec2 instance profile role
module "ec2_instance_profile" {
  source       = "../../modules/iam/ec2-instance-profile"
  project_name = local.project_name
  environment  = local.environment
}

# lauch the data migrate ec2 instance
module "data_migrate_ec2" {
  source                         = "../../modules/data-migrate"
  project_name                   = local.project_name
  environment                    = local.environment
  amazon_linux_ami_id            = local.amazon_linux_ami_id
  ec2_instance_type              = local.ec2_instance_type
  private_app_subnet_az1_id      = module.vpc.private_app_subnet_az1_id
  app_server_security_group_id   = module.security_group.app_server_security_group_id
  ec2_instance_profile_role_name = module.ec2_instance_profile.ec2_instance_profile_role_name
  project_directory              = local.project_directory
  rds_endpoint                   = module.rds.rds_endpoint
  rds_db_username                = module.secret_manager.rds_db_username
  rds_db_password                = module.secret_manager.rds_db_password
  rds_db_name                    = module.secret_manager.rds_db_name
}

# request public ssl certificate from acm
module "ssl_cetificate" {
  source            = "../../modules/acm"
  domain_name       = local.domain_name
  alternative_names = local.alternative_names
}

# create application load balancer 
module "application_load_balancer" {
  source                = "../../modules/alb"
  project_name          = local.project_name
  environment           = local.environment
  alb_security_group_id = module.security_group.alb_security_group_id
  public_subnet_az1_id  = module.vpc.public_subnet_az1_id
  public_subnet_az2_id  = module.vpc.public_subnet_az2_id
  target_type           = "ip"
  vpc_id                = module.vpc.vpc_id
  certificate_arn       = module.ssl_cetificate.certificate_arn
}

# create s3 bucket
module "s3_bucket" {
  source               = "../../modules/s3"
  project_name         = local.project_name
  env_file_bucket_name = local.env_file_bucket_name
  env_file_name        = local.env_file_name
}

# create ecs task execution role
module "ecs_task_execution_role" {
  source               = "../../modules/iam/ecs-task-execution-role"
  project_name         = local.project_name
  environment          = local.environment
  env_file_bucket_name = module.s3_bucket.env_file_bucket_name
}

# create ecs cluster, task definition, and service
module "ecs" {
  source                       = "../../modules/ecs"
  project_name                 = local.project_name
  environment                  = local.environment
  ecs_task_execution_role_arn  = module.ecs_task_execution_role.ecs_task_execution_role_arn
  architecture                 = "X86_64"
  container_image              = local.container_image
  env_file_bucket_name         = module.s3_bucket.env_file_bucket_name
  env_file_name                = module.s3_bucket.env_file_name
  region                       = local.region
  private_app_subnet_az1_id    = module.vpc.private_app_subnet_az1_id
  private_app_subnet_az2_id    = module.vpc.private_app_subnet_az2_id
  app_server_security_group_id = module.security_group.app_server_security_group_id
  alb_target_group_arn         = module.application_load_balancer.alb_target_group_arn
}

# create record set in route 53
module "route_53" {
  source                             = "../../modules/route-53"
  domain_name                        = module.ssl_cetificate.domain_name
  record_name                        = local.record_name
  application_load_balancer_dns_name = module.application_load_balancer.application_load_balancer_dns_name
  application_load_balancer_zone_id  = module.application_load_balancer.application_load_balancer_zone_id
}

# print the website url
output "website_url" {
  value = join("", ["https://", local.record_name, ".", local.domain_name])
}
