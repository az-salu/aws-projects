# Configure SecretProviderClass for AWS Secrets Manager CSI integration
resource "kubernetes_manifest" "aws_provider" {
  manifest = {
    apiVersion = "secrets-store.csi.x-k8s.io/v1"
    kind       = "SecretProviderClass"
    metadata = {
      name      = "${var.project_name}-${var.environment}-eks-secretsmanager" # Must match deployment volume_attributes.secretProviderClass
      namespace = kubernetes_namespace.app_namespace.metadata[0].name         # Reference to the namespace
    }
    spec = {
      provider = "aws"
      parameters = {
        objects = jsonencode([{
          objectName  = "arn:aws:secretsmanager:${var.region}:${var.account_id}:secret:${var.secret_name}-${var.secret_suffix}"  # Must match secret ARN in secrets_policy
          objectAlias = "${var.project_name}-${var.environment}-eks-secrets"
        }])
      }
    }
  }
  depends_on = [
    kubernetes_namespace.app_namespace,
    helm_release.secrets_store_csi_driver,  # Ensure CSI driver is installed
    data.aws_eks_cluster.cluster,           # Ensure cluster data is available
    data.aws_eks_cluster_auth.cluster       # Ensure cluster authentication
  ]
}
