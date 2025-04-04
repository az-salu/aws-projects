# retrieve the secret value stored in secrets manager and parse it as a json object
data "aws_secretsmanager_secret_version" "secrets" {
  secret_id = var.secret_name
}

# store the parsed secret value in a local variable for easier reference
locals {
  secrets = jsondecode(data.aws_secretsmanager_secret_version.secrets.secret_string)
}
