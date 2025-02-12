# Create the CloudWatch log group for EKS cluster logging
resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/${var.project_name}-${var.environment}-eks-cluster/cluster"
  retention_in_days = 30

  tags = {
    Name        = "${var.project_name}-${var.environment}-eks-logs"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
