output "account_id" {
  description = "Account the layer was applied to."
  value       = data.aws_caller_identity.current.account_id
}

output "name_prefix" {
  description = "Name prefix for platform-level resources in this environment."
  value       = module.context.prefix
}

output "environment_parameter" {
  description = "Parameter Store name holding the environment's identity."
  value       = aws_ssm_parameter.environment.name
}
