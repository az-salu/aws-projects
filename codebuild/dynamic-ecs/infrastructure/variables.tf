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

variable "secret_arn" {
  description = "Name of the Secrets Manager secret"
  type        = string
}

variable "source_branch" {
  description = "Branch to build from"
  type        = string
}

variable "build_environment_type" {
  description = "Type of build environment"
  type        = string
}

variable "build_compute_type" {
  description = "Size of the build environment compute resources"
  type        = string
}

variable "build_image" {
  description = "Docker image to use for the build environment"
  type        = string
}

variable "github_username" {
  description = "GitHub username"
  type        = string
}

variable "source_type" {
  description = "Type of source provider"
  type        = string
}

variable "source_location" {
  description = "Location of the source code"
  type        = string
}

variable "buildspec_file" {
  description = "Path to the buildspec file"
  type        = string
}
