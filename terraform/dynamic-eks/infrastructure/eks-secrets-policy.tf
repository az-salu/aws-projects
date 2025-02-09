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