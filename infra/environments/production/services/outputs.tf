output "sample_image" {
  description = "Image of the sample service that this apply deployed."
  value       = local.sample_image
}

output "sample_service_name" {
  description = "Name of the sample service on ECS."
  value       = module.sample_service.service_name
}
