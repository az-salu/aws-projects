# Create an IAM role for the service account
resource "aws_iam_role" "service_account_role" {
  name = "${var.project_name}-${var.environment}-eks-sa-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn # Reference to OIDC provider
        }
        Condition = {
          StringEquals = {
            # Must match the service account namespace and name for IRSA to work
            # "${replace(var.eks_cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:${var.project_name}-${var.environment}-eks-namespace:${var.project_name}-${var.environment}-eks-service-account"
            "${replace(var.eks_cluster_oidc_issuer_url, "https://", "")}:aud": "sts.amazonaws.com",
            "${replace(var.eks_cluster_oidc_issuer_url, "https://", "")}:sub": "system:serviceaccount:${var.project_name}-${var.environment}-eks-namespace:${var.project_name}-${var.environment}-eks-service-account"

          }
        }
      }
    ]
  })
}

# Define the policy document for accessing secrets
data "aws_iam_policy_document" "secrets_policy" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [
      "arn:aws:secretsmanager:${var.region}:${var.account_id}:secret:${var.secret_name}-${var.secret_suffix}" # Must match SecretProviderClass objectName
    ]
  }
}

# Create the standalone IAM policy
resource "aws_iam_policy" "secrets_policy" {
  name        = "${var.project_name}-${var.environment}-eks-secrets-policy"
  description = "Policy for accessing Secrets Manager"
  policy      = data.aws_iam_policy_document.secrets_policy.json
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "secrets_policy_attachment" {
  role       = aws_iam_role.service_account_role.name
  policy_arn = aws_iam_policy.secrets_policy.arn
}

# Create the Kubernetes service account
resource "kubernetes_service_account" "app_service_account" {
  metadata {
    name      = "${var.project_name}-${var.environment}-eks-service-account" # Must match role assumption policy and deployment serviceAccountName
    namespace = kubernetes_namespace.app_namespace.metadata[0].name          # Reference to namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.service_account_role.arn
    }
  }
  depends_on = [kubernetes_namespace.app_namespace]
}
