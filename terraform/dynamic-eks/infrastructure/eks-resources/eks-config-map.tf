# # Get existing aws-auth ConfigMap data
# data "kubernetes_config_map" "aws_auth" {
#  metadata {
#    name      = "aws-auth"
#    namespace = "kube-system"
#  }
# }

# # Update existing aws-auth ConfigMap with new user/role mappings
# resource "kubernetes_config_map_v1_data" "aws_auth_users" {
#  metadata {
#    name      = "aws-auth"
#    namespace = "kube-system"
#  }

#  # Define IAM user and role mappings
#  data = {
#    # Grant admin access to specified IAM user
#    mapUsers = yamlencode([
#      {
#        userarn  = "arn:aws:iam::${var.account_id}:user/${var.admin_username}"
#        username = var.admin_username
#        groups   = ["system:masters"]
#      }
#    ])

#    # Grant access to specified IAM roles
#    mapRoles = yamlencode([
#      # Admin access for role1
#      {
#        rolearn  = "arn:aws:iam::${var.account_id}:role/role1"
#        username = "role1"
#        groups   = ["system:masters"]
#      },
#      # Worker node role access
#      {
#        rolearn  = aws_iam_role.eks_worker_node_role.arn
#        username = "system:node:{{EC2PrivateDNSName}}"
#        groups   = ["system:bootstrappers", "system:nodes"]
#      }
#    ])
#  }

#  # Force apply changes to existing ConfigMap
#  force = true
# }


# Create aws-auth ConfigMap to grant IAM user/role access to the EKS cluster
resource "kubernetes_config_map" "aws_auth" {
  metadata {
    name      = "aws-auth"
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
        rolearn  = aws_iam_role.eks_worker_node_role.arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = ["system:bootstrappers", "system:nodes"]
      }
    ])
  }
}