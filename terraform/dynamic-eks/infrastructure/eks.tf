# create an iam role for eks cluster
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
}

# attach policies to the eks cluster iam role
resource "aws_iam_role_policy_attachment" "eks_AmazonEKSClusterPolicy" {
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

# create the eks cluster
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
    aws_iam_role_policy_attachment.eks_AmazonEKSVPCResourceController
  ]

  tags = {
    Name = "${var.project_name}-${var.environment}-eks-cluster"
  }
}

# create an iam role for the node group
resource "aws_iam_role" "eks_worker_node_role" {
  name = "${var.project_name}-${var.environment}-eks-worker-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

# attach AmazonEKSWorkerNodePolicy to the iam role
resource "aws_iam_role_policy_attachment" "worker_node_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_worker_node_role.name
}

# attach AmazonEC2ContainerRegistryReadOnly to the iam role
resource "aws_iam_role_policy_attachment" "worker_node_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_worker_node_role.name
}

# attach AmazonEKS_CNI_Policy to the iam role
resource "aws_iam_role_policy_attachment" "worker_node_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_worker_node_role.name
}

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

# create the namespace 
resource "kubernetes_namespace" "app_namespace" {
  metadata {
    name = "${var.project_name}-${var.environment}-eks-namespace"
  }
}

# helm csi driver installation
resource "helm_release" "secrets_store_csi_driver" {
  name       = "csi-secrets-store"
  repository = "https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts"
  chart      = "secrets-store-csi-driver"
  namespace  = "kube-system"

  set {
    name  = "syncSecret.enabled"
    value = "true"
  }

  set {
    name  = "enableSecretRotation"
    value = "true"
  }
}

# aws provider installation
resource "kubernetes_manifest" "aws_provider" {
  manifest = {
    apiVersion = "secrets-store.csi.x-k8s.io/v1"
    kind       = "SecretProviderClass"
    metadata = {
      name      = "${var.project_name}-${var.environment}-eks-secretsmanager" # must match deployment volume_attributes.secretProviderClass
      namespace = kubernetes_namespace.app_namespace.metadata[0].name         # using reference to namespace
    }
    spec = {
      provider = "aws"
      parameters = {
        objects = jsonencode([{
          objectName  = "arn:aws:secretsmanager:${var.region}:${var.account_id}:secret:${var.secret_name}-${var.secret_suffix}"  # must match secret arn in secrets_policy
          objectAlias = "${var.project_name}-${var.environment}-eks-secrets"
        }])
      }
    }
  }
  depends_on = [kubernetes_namespace.app_namespace]
}

# get tls certificate for oidc provider
data "tls_certificate" "eks" {
  url = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
}

# oidc provider association
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer  # using reference to eks cluster oidc issuer
}

# create iam role for service account
resource "aws_iam_role" "service_account_role" {
  name = "${var.project_name}-${var.environment}-eks-sa-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn  # using reference to oidc provider
        }
        Condition = {
          StringEquals = {
            # must match service account namespace and name for irsa to work
            "${replace(aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:${var.project_name}-${var.environment}-app:${var.project_name}-${var.environment}-eks-service-account"
          }
        }
      }
    ]
  })
}

# define the policy document for secrets access
data "aws_iam_policy_document" "secrets_policy" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [
      "arn:aws:secretsmanager:${var.region}:${var.account_id}:secret:${var.secret_name}-${var.secret_suffix}"  # must match SecretProviderClass objectName
    ]
  }
}

# create the standalone iam policy
resource "aws_iam_policy" "secrets_policy" {
  name        = "${var.project_name}-${var.environment}-eks-secrets-policy"
  description = "policy for accessing secrets manager"
  policy      = data.aws_iam_policy_document.secrets_policy.json 
}

# attach the policy to the role
resource "aws_iam_role_policy_attachment" "secrets_policy_attachment" {
  role       = aws_iam_role.service_account_role.name  
  policy_arn = aws_iam_policy.secrets_policy.arn      
}

# create service account
resource "kubernetes_service_account" "app_service_account" {
  metadata {
    name      = "${var.project_name}-${var.environment}-eks-service-account"  # must match role assumption policy and deployment serviceAccountName
    namespace = kubernetes_namespace.app_namespace.metadata[0].name           # using reference to namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.service_account_role.arn  
    }
  }
  depends_on = [kubernetes_namespace.app_namespace]
}

# create aws-auth configmap to enable iam user/role access to the eks cluster
resource "kubernetes_config_map" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"  # must be in kube-system namespace
  }

  data = {
    # granting a user access 
    mapUsers = yamlencode([
      {
        userarn  = "arn:aws:iam::${var.account_id}:user/${var.admin_username}"
        username = var.admin_username
        groups   = ["system:masters"]
      }
    ])

    # granting a role access 
    mapRoles = yamlencode([
      {
        rolearn  = "arn:aws:iam::${var.account_id}:role/role1"
        username = "role1"
        groups   = ["system:masters"]
      }
    ])
  }
}

# deploy the application
resource "kubernetes_deployment" "app_deployment" {
  metadata {
    name      = "${var.project_name}-${var.environment}-eks-deployment"
    namespace = kubernetes_namespace.app_namespace.metadata[0].name  # using reference to namespace
    labels = {
      app = "${var.project_name}-${var.environment}-eks-app"  # must match service selector
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "${var.project_name}-${var.environment}-eks-app"  # must match template labels and service selector
      }
    }

    template {
      metadata {
        labels = {
          app = "${var.project_name}-${var.environment}-eks-app"  # must match selector match_labels
        }
      }

      spec {
        service_account_name = kubernetes_service_account.app_service_account.metadata[0].name  # using reference to service account

        container {
          name  = "${var.project_name}-${var.environment}-eks-container"
          image = "${var.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.project_name}:latest"

          port {
            container_port = 80  # must match service port
          }

          volume_mount {
            name       = "secrets-store-inline"  # must match volume name
            mount_path = "/mnt/secrets-store"
            read_only  = true
          }
        }

        volume {
          name = "secrets-store-inline"  # must match volume_mount name
          csi {
            driver    = "secrets-store.csi.k8s.io"
            read_only = true
            volume_attributes = {
              secretProviderClass = "${var.project_name}-${var.environment}-eks-secretsmanager"  # must match SecretProviderClass name
            }
          }
        }
      }
    }
  }
}

# create the service
resource "kubernetes_service" "app_service" {
  metadata {
    name      = "${var.project_name}-app"
    namespace = kubernetes_namespace.app_namespace.metadata[0].name  # using reference to namespace
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type"                            = "nlb"
      "service.beta.kubernetes.io/aws-load-balancer-internal"                        = "false"
      "service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled" = "true"
    }
  }

  spec {
    type = "LoadBalancer"
    port {
      name = "web"
      port = 80  # must match deployment container port
    }
    selector = {
      app = "${var.project_name}-${var.environment}-eks-app"  # must match deployment labels
    }
  }
}
