output "bucket" {
  description = "Name of the state bucket."
  value       = aws_s3_bucket.state.id
}

output "bucket_arn" {
  description = "ARN of the state bucket."
  value       = aws_s3_bucket.state.arn
}

output "kms_key_arn" {
  description = "ARN of the key that encrypts state."
  value       = aws_kms_key.state.arn
}

output "kms_key_alias" {
  description = "Alias of the key that encrypts state."
  value       = aws_kms_alias.state.name
}
