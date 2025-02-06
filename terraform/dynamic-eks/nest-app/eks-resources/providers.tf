# Create a provider block for the AWS provider. This provider is used to interact with AWS resources.
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

# Create a Kubernetes provider. This provider is used to interact with Kubernetes resources in the EKS cluster.
provider "kubernetes" {
  host                   = data.terraform_remote_state.cluster.outputs.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.cluster.outputs.eks_cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.cluster.outputs.eks_cluster_name]
    command     = "aws"
  }
}

# Create a Helm provider. This provider is used to interact with Helm charts in the EKS cluster.
provider "helm" {
  kubernetes {
    host                   = data.terraform_remote_state.cluster.outputs.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(data.terraform_remote_state.cluster.outputs.eks_cluster_ca_certificate)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.cluster.outputs.eks_cluster_name]
      command     = "aws"
    }
  }
}
