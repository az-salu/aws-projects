# Install the CSI Secrets Store Driver using Helm
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
