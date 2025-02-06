# Deploy the application
resource "kubernetes_deployment" "app_deployment" {
  metadata {
    name      = "${var.project_name}-${var.environment}-eks-deployment"
    namespace = kubernetes_namespace.app_namespace.metadata[0].name # Reference to the namespace
    labels = {
      app = "${var.project_name}-${var.environment}-eks-app" # Must match the service selector
    }
  }

  spec {
    replicas = 1

    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_surge       = 1
        max_unavailable = 0
      }
    }

    selector {
      match_labels = {
        app = "${var.project_name}-${var.environment}-eks-app" # Must match template labels and service selector
      }
    }

    template {
      metadata {
        labels = {
          app = "${var.project_name}-${var.environment}-eks-app" # Must match selector match_labels
        }
      }

      spec {
        service_account_name = kubernetes_service_account.app_service_account.metadata[0].name # Reference to the service account

        affinity {
          pod_anti_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 100
              pod_affinity_term {
                label_selector {
                  match_expressions {
                    key      = "app"
                    operator = "In"
                    values   = ["${var.project_name}-${var.environment}-eks-app"] # Must match selector match_labels
                  }
                }
                topology_key = "kubernetes.io/hostname"
              }
            }
          }
        }

        container {
          name  = "${var.project_name}-${var.environment}-eks-container"
          image = "${var.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.project_name}:latest"

          port {
            container_port = 80
            protocol       = "TCP"
          }

          resources {
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
            requests = {
              cpu    = "250m"
              memory = "256Mi"
            }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 80
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 80
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }
          startup_probe {
            http_get {
              path = "/health"
              port = 80
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            failure_threshold     = 30
          }

          volume_mount {
            name       = "secrets-store-inline" # Must match volume name
            mount_path = "/mnt/secrets-store"
            read_only  = true
          }
        }

        volume {
          name = "secrets-store-inline" # Must match volume_mount name
          csi {
            driver    = "secrets-store.csi.k8s.io"
            read_only = true
            volume_attributes = {
              secretProviderClass = "${var.project_name}-${var.environment}-eks-secretsmanager" # Must match SecretProviderClass name
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_service_account.app_service_account,
    kubernetes_manifest.aws_provider
  ]
}
