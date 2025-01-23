# create the namespace 
resource "kubernetes_namespace" "app_namespace" {
  metadata {
    name = "${var.project_name}-${var.environment}-namespace"
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
      name      = "${var.project_name}-${var.environment}-secretsmanager" 
      namespace = kubernetes_namespace.app_namespace.metadata[0].name
    }
    spec = {
      provider = "aws"
      parameters = {
        objects = jsonencode([{
          objectName  = "arn:aws:secretsmanager:${var.region}:${var.account_id}:secret:${var.secret_name}-${var.secret_suffix}"
          objectAlias = "${var.project_name}-${var.environment}-secrets"
        }])
      }
    }
  }
  depends_on = [kubernetes_namespace.app_namespace]
}

# oidc provider association
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
}

# create service account
resource "kubernetes_service_account" "app_service_account" {
  metadata {
    name      = "${var.project_name}-${var.environment}-service-account"
    namespace = kubernetes_namespace.app_namespace.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.service_account_role.arn
    }
  }
  depends_on = [kubernetes_namespace.app_namespace]
}

# create iam role for service account
resource "aws_iam_role" "service_account_role" {
  name = "${var.project_name}-${var.environment}-sa-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Condition = {
          StringEquals = {
            "${replace(aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:${kubernetes_namespace.app_namespace.metadata[0].name}:${kubernetes_service_account.app_service_account.metadata[0].name}"
          }
        }
      }
    ]
  })
}

# add iam policy for secrets manager access
resource "aws_iam_role_policy" "service_account_policy" {
  name = "${var.project_name}-${var.environment}-sa-policy"
  role = aws_iam_role.service_account_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "arn:aws:secretsmanager:${var.region}:${var.account_id}:secret:${var.secret_name}-${var.secret_suffix}"
      }
    ]
  })
}
