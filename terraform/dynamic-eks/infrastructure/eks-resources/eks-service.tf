# Create the Kubernetes service
resource "kubernetes_service" "app_service" {
  metadata {
    name      = "${var.project_name}-app"
    namespace = kubernetes_namespace.app_namespace.metadata[0].name  # Reference to the namespace
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type"                              = "nlb"
      "service.beta.kubernetes.io/aws-load-balancer-internal"                          = "false"
      "service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled" = "true"
      "service.beta.kubernetes.io/aws-load-balancer-connection-idle-timeout"           = "60"
    }
  }

  spec {
    type = "LoadBalancer"
    port {
      name        = "http"
      port        = 80
      target_port = 80
      protocol    = "TCP"
    }
    selector = {
      app = "${var.project_name}-${var.environment}-eks-app"  # Must match the deployment labels

    health_check_grace_period_seconds = 300
    session_affinity = "ClientIP"
    external_traffic_policy = "Local"
    }
  }

  depends_on = [kubernetes_deployment.app_deployment]
}
