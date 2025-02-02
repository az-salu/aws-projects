# Output the service load balancer hostname
output "service_load_balancer_hostname" {
  description = "Service load balancer hostname"
  value       = kubernetes_service_account.app_service_account.status.0.load_balancer.0.ingress.0.hostname
}