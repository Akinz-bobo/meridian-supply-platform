output "read_policy_json" {
  description = "IAM policy that lets a role read this service's parameters and secrets, and nothing else. Attach it to the service's workload role."
  value       = data.aws_iam_policy_document.read.json
}

output "parameter_path" {
  description = "Path to read all plain configuration from with one GetParametersByPath call."
  value       = "${var.path}/config"
}

output "parameter_names" {
  description = "Full names of the parameters, keyed by the short name."
  value       = { for key, parameter in aws_ssm_parameter.config : key => parameter.name }
}

output "secret_arns" {
  description = "ARNs of the secrets, keyed by name. Reference these from a task definition or function, never the value."
  value       = { for name, secret in aws_secretsmanager_secret.this : name => secret.arn }
}

output "secret_names" {
  description = "Full names of the secrets, keyed by the short name."
  value       = { for name, secret in aws_secretsmanager_secret.this : name => secret.name }
}
