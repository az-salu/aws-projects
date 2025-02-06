# Environment variables
variable "account_id" {
  description = "AWS account ID"
  type        = string
}

variable "region" {
  description = "AWS region for resource creation"
  type        = string
}

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g., dev, prod)"
  type        = string
}

# VPC variables
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "public_subnet_az1_cidr" {
  description = "CIDR block for public subnet in AZ1"
  type        = string
}

variable "public_subnet_az2_cidr" {
  description = "CIDR block for public subnet in AZ2"
  type        = string
}

variable "private_app_subnet_az1_cidr" {
  description = "CIDR block for private app subnet in AZ1"
  type        = string
}

variable "private_app_subnet_az2_cidr" {
  description = "CIDR block for private app subnet in AZ2"
  type        = string
}

variable "private_data_subnet_az1_cidr" {
  description = "CIDR block for private data subnet in AZ1"
  type        = string
}

variable "private_data_subnet_az2_cidr" {
  description = "CIDR block for private data subnet in AZ2"
  type        = string
}

# Secrets Manager variables
variable "secret_name" {
  description = "Name of the secret in AWS Secrets Manager"
  type        = string
}

variable "secret_suffix" {
  description = "Random suffix for the secret in AWS Secrets Manager"
  type        = string
}

# RDS variables
variable "multi_az_deployment" {
  description = "Enable Multi-AZ deployment for RDS"
  type        = bool
}

variable "database_instance_identifier" {
  description = "Identifier for the RDS instance"
  type        = string
}

variable "database_instance_class" {
  description = "Instance type for the RDS instance"
  type        = string
}

variable "publicly_accessible" {
  description = "Whether the RDS instance is publicly accessible"
  type        = bool
}

# EKS variables
variable "eks_cluster_version" {
  description = "Version of the EKS cluster"
  type        = string
}

variable "public_access_cidrs" {
  description = "CIDR blocks allowed for public access to EKS"
  type        = list(string)
}

# Data migration EC2 instance
variable "s3_uri" {
  description = "S3 URI for the SQL data migration script"
  type        = string
}
variable "amazon_linux_ami_id" {
  description = "AMI ID for Amazon Linux"
  type        = string
}

variable "ec2_instance_type" {
  description = "Instance type for the EC2 instance"
  type        = string
}
