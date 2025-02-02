# Environment variables
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

variable "project_directory" {
  description = "Directory name where the project is located"
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
  description = "Name of the Secrets Manager secret"
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
  description = "Instance class/type for the RDS instance"
  type        = string
}

variable "publicly_accessible" {
  description = "Whether the RDS instance is publicly accessible"
  type        = bool
}

# ALB variables
variable "target_type" {
  description = "Type of target for ALB (e.g., ip, instance, lambda)"
  type        = string
}
variable "health_check_path" {
  description = "Health check path for ALB target group"
  type        = string
  default     = "/"
}

# ACM variables
variable "domain_name" {
  description = "Primary domain name"
  type        = string
}

variable "alternative_names" {
  description = "Alternative domain names (subdomains)"
  type        = string
}

# SNS Topic variables
variable "operator_email" {
  description = "Valid email address for SNS topic"
  type        = string
}

# Auto Scaling Group variables
variable "amazon_linux_ami_id" {
  description = "AMI ID for Amazon Linux"
  type        = string
}

variable "ec2_instance_type" {
  description = "Instance type for EC2 instances"
  type        = string
}

# Route 53 variables
variable "record_name" {
  description = "Record name for Route 53"
  type        = string
}
