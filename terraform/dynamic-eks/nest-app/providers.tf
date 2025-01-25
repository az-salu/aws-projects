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

# configure kubernetes provider with EKS cluster details
provider "kubernetes" {
  host                   = aws_eks_cluster.eks_cluster.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.eks_cluster.certificate_authority[0].data)
  
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.eks_cluster.name]
    command     = "aws"
  }
}

# configure helm provider (needed for csi driver installation)
provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.eks_cluster.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.eks_cluster.certificate_authority[0].data)
    
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.eks_cluster.name]
      command     = "aws"
    }
  }
}