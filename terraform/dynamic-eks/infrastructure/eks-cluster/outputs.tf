# Output the AWS account ID
output "account_id" {
  description = "AWS account ID"
  value       = var.account_id
}

# Output the AWS region
output "region" {
  description = "AWS region"
  value       = var.region
}

# Output the project name
output "project_name" {
  description = "Project name"
  value       = var.project_name
}

# Output the environment name
output "environment" {
  description = "Environment name"
  value       = var.environment
}

# Output the EKS cluster name
output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.eks_cluster.name
}

# Output the EKS cluster endpoint
output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = aws_eks_cluster.eks_cluster.endpoint
}

# Output the EKS cluster CA certificate
output "eks_cluster_ca_certificate" {
  description = "EKS cluster CA certificate"
  value       = aws_eks_cluster.eks_cluster.certificate_authority[0].data
}

# Output the EKS cluster OIDC issuer URL
output "eks_cluster_oidc_issuer_url" {
  description = "EKS cluster OIDC issuer URL"
  value       = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
}

# Output the ARN of the EKS Worker Node IAM Role
output "eks_worker_node_role_arn" {
  description = "ARN of the EKS Worker Node IAM Role"
  value       = aws_iam_role.eks_worker_node_role.arn
}
