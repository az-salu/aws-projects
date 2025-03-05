# Configure AWS provider to establish a secure connection between Terraform and AWS
provider "aws" {
  region  = local.region
  
  default_tags {
    tags = {
      "Automation"  = "terraform"
      "Project"     = local.project_name
      "Environment" = local.environment
    }
  }
}
