# export the rds database username
output "rds_db_username" {
  value = local.secrets.username
}

# export the rds database password
output "rds_db_password" {
  value = local.secrets.password
}

# export the rds database name
output "rds_db_name" {
  value = local.secrets.db_name
}
