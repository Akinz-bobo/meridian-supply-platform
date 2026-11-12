output "identifier" {
  description = "Identifier of the database instance."
  value       = aws_db_instance.this.identifier
}

output "arn" {
  description = "ARN of the database instance."
  value       = aws_db_instance.this.arn
}

output "address" {
  description = "Host name to connect to. Read it together with port, and do not assume 5432."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "Port to connect to."
  value       = aws_db_instance.this.port
}

output "database_name" {
  description = "Name of the database inside the instance."
  value       = aws_db_instance.this.db_name
}

output "resource_id" {
  description = "Immutable identifier of the instance, used in the ARN that grants IAM database authentication: arn:aws:rds-db:<region>:<account>:dbuser:<resource_id>/<user>."
  value       = aws_db_instance.this.resource_id
}

output "master_user_secret_arn" {
  description = "ARN of the secret that holds the master user's credentials. Managed and rotated by RDS. Applications do not use the master user."
  value       = one(aws_db_instance.this.master_user_secret[*].secret_arn)
}

output "log_group_name" {
  description = "Log group that receives the database's logs."
  value       = aws_cloudwatch_log_group.postgresql.name
}
