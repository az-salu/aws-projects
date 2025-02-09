# Fetch the secret value from AWS Secrets Manager and parse it as a JSON object
data "aws_secretsmanager_secret_version" "secrets" {
  secret_id = var.secret_name
}
