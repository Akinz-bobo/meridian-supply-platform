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

output "vpc_id" {
  description = "Identifier of the environment's VPC."
  value       = module.vpc.vpc_id
}

output "nat_public_ips" {
  description = "Public addresses outbound traffic from the private subnets comes from."
  value       = module.vpc.nat_public_ips
}
