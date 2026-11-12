output "name_prefix" {
  description = "Prefix of every resource in this layer."
  value       = module.context.prefix
}

output "foundation_facts" {
  description = "What this layer read from the foundation layer, for checking that the two are wired together."
  value       = keys(local.facts)
}
