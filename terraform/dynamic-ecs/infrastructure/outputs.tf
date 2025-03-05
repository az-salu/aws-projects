# Output variables to expose infrastructure resources for deployment automation and reference
output "image_name" {
  value = var.image_name
}

output "image_tag" {
  value = var.image_tag
}

output "domain_name" {
  value = var.domain_name
}

output "rds_endpoint" {
  value = aws_db_instance.database_instance.endpoint
}

output "ecs_task_definition_name" {
  value = aws_ecs_task_definition.ecs_task_definition.family
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.ecs_cluster.name
}

output "ecs_service_name" {
  value = aws_ecs_service.ecs_service.name
}