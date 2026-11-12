output "vault_name" {
  description = "Name of the backup vault."
  value       = aws_backup_vault.this.name
}

output "vault_arn" {
  description = "ARN of the backup vault."
  value       = aws_backup_vault.this.arn
}

output "plan_id" {
  description = "Identifier of the backup plan."
  value       = aws_backup_plan.this.id
}

output "role_arn" {
  description = "ARN of the role the backup service uses."
  value       = aws_iam_role.this.arn
}

output "selection_tag" {
  description = "Tag that opts a resource in to this plan. Put it on a store to have it backed up."
  value       = var.selection_tag
}
