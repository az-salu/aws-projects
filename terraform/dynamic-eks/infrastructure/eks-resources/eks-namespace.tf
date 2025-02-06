# Create the Kubernetes namespace
resource "kubernetes_namespace" "app_namespace" {
  metadata {
    name = "${var.project_name}-${var.environment}-eks-namespace"

    labels = {
      name        = "${var.project_name}-${var.environment}-eks-namespace"
      environment = var.environment
    }
  }
}
