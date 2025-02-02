# configure aws provider to establish a secure connection between terraform and aws
provider "aws" {
  region  = local.region
  profile = "cloud-projects"

  default_tags {
    tags = {
      "Automation"  = "terraform"
      "Project"     = local.project_name
      "Environment" = local.environment
    }
  }
}

# configure kubernetes provider with eks cluster details
provider "kubernetes" {
  host                   = module.nest-app.cluster_endpoint
  cluster_ca_certificate = base64decode(module.nest-app.cluster_ca_certificate)
  
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", module.nest-app.cluster_name]
    command     = "aws"
  }
}

# configure helm provider
provider "helm" {
  kubernetes {
    host                   = module.nest-app.cluster_endpoint
    cluster_ca_certificate = base64decode(module.nest-app.cluster_ca_certificate)
    
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", module.nest-app.cluster_name]
      command     = "aws"
    }
  }
}