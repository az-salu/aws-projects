# Create aws-auth ConfigMap to grant IAM user/role access to the EKS cluster
resource "kubernetes_config_map" "aws_auth" {
  metadata {
    name      = "aws-auth"     # Must be aws-auth
    namespace = "kube-system"  # Must be in the kube-system namespace
  }

  data = {
    # Granting a user access
    mapUsers = yamlencode([
      {
        userarn  = "arn:aws:iam::${var.account_id}:user/${var.admin_username}"
        username = var.admin_username
        groups   = ["system:masters"]
      }
    ])

    # Granting a role access
    mapRoles = yamlencode([
      {
        rolearn  = "arn:aws:iam::${var.account_id}:role/role1"
        username = "role1"
        groups   = ["system:masters"]
      },
      {
        rolearn  = var.eks_worker_node_role_arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = ["system:bootstrappers", "system:nodes"]
      }
    ])
  }
}
