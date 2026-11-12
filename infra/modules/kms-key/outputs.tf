output "key_arn" {
  description = "ARN of the key. Use this wherever a resource asks for a KMS key."
  value       = aws_kms_key.this.arn
}

output "key_id" {
  description = "Identifier of the key."
  value       = aws_kms_key.this.key_id
}

output "alias_name" {
  description = "Alias of the key, including the alias/ prefix."
  value       = aws_kms_alias.this.name
}

output "alias_arn" {
  description = "ARN of the alias. IAM policies can grant use of a key by alias."
  value       = aws_kms_alias.this.arn
}
