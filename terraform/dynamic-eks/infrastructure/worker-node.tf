# create launch template
resource "aws_launch_template" "eks_node_template" {
  name = "${var.project_name}-${var.environment}-eks-node-template"

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 20
      volume_type = "gp3"
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project_name}-${var.environment}-eks-worker-node"
      Environment = var.environment
    }
  }
}

# create the node group
resource "aws_eks_node_group" "worker_node" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_group_name = "${var.project_name}-${var.environment}-eks-worker-node"
  node_role_arn   = aws_iam_role.eks_worker_node_role.arn
  subnet_ids = [
    aws_subnet.private_app_subnet_az1.id,
    aws_subnet.private_app_subnet_az2.id
  ]

  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }

  labels = {
    role = "worker"
    type = "private"
  }

  ami_type       = "AL2023_x86_64_STANDARD"
  instance_types = ["t3.medium"]
  capacity_type  = "ON_DEMAND"

  depends_on = [
    aws_iam_role_policy_attachment.worker_node_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.worker_node_AmazonEC2ContainerRegistryReadOnly,
    aws_iam_role_policy_attachment.worker_node_AmazonEKS_CNI_Policy,
  ]

  update_config {
    max_unavailable = 1
  }

  launch_template {
    id      = aws_launch_template.eks_node_template.id
    version = aws_launch_template.eks_node_template.latest_version
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-eks-worker-node"
    Environment = var.environment
  }

  lifecycle {
    create_before_destroy = true
  }
}
