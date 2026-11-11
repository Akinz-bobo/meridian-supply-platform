output "prefix" {
  description = "Name prefix: <project>-<environment>-<component>. Append a qualifier for sibling resources."
  value       = local.prefix
}

output "tags" {
  description = "Standard tags, plus any extra tags that do not collide with them."
  value       = local.tags
}

output "ssm_path" {
  description = "Parameter Store path for this component: /<project>/<environment>/<component>."
  value       = "/${var.project}/${var.environment}/${var.component}"
}

output "environment" {
  description = "The environment, passed through for convenience."
  value       = var.environment
}
