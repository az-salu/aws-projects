# configure aws provider to establish a secure connection between terraform and aws
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