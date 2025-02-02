# Retrieve the TLS certificate for the OIDC provider
data "tls_certificate" "eks" {
  url = var.eks_cluster_oidc_issuer_url # Reference to the EKS cluster OIDC issuer
}

# Associate the OIDC provider with IAM
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = var.eks_cluster_oidc_issuer_url # Reference to the EKS cluster OIDC issuer
}
