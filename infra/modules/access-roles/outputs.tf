output "deploy_role_arn" {
  description = "ARN of the role GitHub Actions assumes. Set it as role-to-assume in the workflow."
  value       = aws_iam_role.deploy.arn
}

output "operator_role_arn" {
  description = "ARN of the role on-call engineers assume."
  value       = aws_iam_role.operator.arn
}

output "audit_role_arn" {
  description = "ARN of the role security reviewers assume."
  value       = aws_iam_role.audit.arn
}

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub OpenID Connect provider in this account."
  value       = aws_iam_openid_connect_provider.github.arn
}
