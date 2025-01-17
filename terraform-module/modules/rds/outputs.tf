# export the rds endpoint
output "rds_endpoint" {
  value = aws_db_instance.database_instance.endpoint
}
