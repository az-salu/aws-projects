# website url
output "website_url" {
  value = join("", ["https://", local.record_name, ".", local.domain_name])
}
