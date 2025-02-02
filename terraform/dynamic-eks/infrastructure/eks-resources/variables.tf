# Environment variables
variable "account_id" {
  description = "The AWS account ID"
  type        = string
}

variable "region" {
  description = "The AWS region where resources will be created"
  type        = string
}

variable "project_name" {
  description = "The name of the project"
  type        = string
}

variable "environment" {
  description = "The deployment environment (e.g., dev, prod)"
  type        = string
}

# Config map variables
variable "admin_username" {
  type        = string
  description = "The IAM username for the cluster administrator"
}

# Secret provider variables
variable "secret_name" {
  description = "The name of the secret in AWS Secrets Manager"
  type        = string
}

variable "secret_suffix" {
  type        = string
  description = "A random suffix for the secret in AWS Secrets Manager"
}
