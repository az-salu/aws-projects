# Output variables to expose infrastructure resources for deployment automation and reference
output "image_name" {
  value = module.shopwise-app.image_name
}

output "image_tag" {
  value = module.shopwise-app.image_tag
}

output "domain_name" {
  value = join("", [local.record_name, ".", local.domain_name])
}

output "rds_endpoint" {
  value = module.shopwise-app.rds_endpoint
}

output "ecs_task_definition_name" {
  value = module.shopwise-app.ecs_task_definition_name
}

output "ecs_cluster_name" {
  value = module.shopwise-app.ecs_cluster_name
}

output "ecs_service_name" {
  value = module.shopwise-app.ecs_service_name
}
output "website_url" {
  value = join("", ["https://", local.record_name, ".", local.domain_name])
}