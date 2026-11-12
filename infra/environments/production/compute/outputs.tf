output "name_prefix" {
  description = "Prefix of the shared resources in this layer."
  value       = module.context.prefix
}

output "sample_repository_url" {
  description = "Where the sample service's image is pushed."
  value       = module.sample_repository.repository_url
}
