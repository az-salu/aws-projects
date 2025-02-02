# Create an IAM role for EKS cluster
resource "aws_iam_role" "eks_cluster_role" {
  name = "${var.project_name}-${var.environment}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "eks.amazonaws.com"
        }
      },
    ]
  })
  tags = {
    Name        = "${var.project_name}-${var.environment}-eks-cluster-role"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Create IAM role policies for EKS cluster management
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_iam_role_policy_attachment" "eks_AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_iam_role_policy_attachment" "eks_AmazonEKSVPCResourceController" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster_role.name
}

# Create the EKS cluster
resource "aws_eks_cluster" "eks_cluster" {
  name = "${var.project_name}-${var.environment}-eks-cluster"

  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids = [
      aws_subnet.private_app_subnet_az1.id,
      aws_subnet.private_app_subnet_az2.id
    ]

    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.public_access_cidrs
  }

  kubernetes_network_config {
    ip_family = "ipv4"
  }

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  depends_on = [
    aws_iam_role_policy_attachment.eks_AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.eks_AmazonEKSServicePolicy,
    aws_iam_role_policy_attachment.eks_AmazonEKSVPCResourceController,
    aws_cloudwatch_log_group.eks_cluster
  ]

  tags = {
    Name        = "${var.project_name}-${var.environment}-eks-cluster"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Configure the VPC CNI addon for networking
# This addon enables pod networking within the EKS cluster
resource "aws_eks_addon" "vpc_cni" {
  cluster_name      = aws_eks_cluster.eks_cluster.name
  addon_name        = "vpc-cni"
  addon_version     = "v1.12.6-eksbuild.1"
}

# Configure the CoreDNS addon for DNS resolution
# This addon provides DNS-based service discovery for the cluster
resource "aws_eks_addon" "coredns" {
  cluster_name      = aws_eks_cluster.eks_cluster.name
  addon_name        = "coredns"
  addon_version     = "v1.10.1-eksbuild.1"
}

# Configure the kube-proxy addon for network proxying
# This addon maintains network rules on each node for container communication
resource "aws_eks_addon" "kube_proxy" {
  cluster_name      = aws_eks_cluster.eks_cluster.name
  addon_name        = "kube-proxy"
  addon_version     = "v1.27.1-eksbuild.1"
}
