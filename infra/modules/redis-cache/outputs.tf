output "replication_group_id" {
  description = "Identifier of the replication group."
  value       = aws_elasticache_replication_group.this.id
}

output "arn" {
  description = "ARN of the replication group."
  value       = aws_elasticache_replication_group.this.arn
}

output "primary_endpoint_address" {
  description = "Host name for writes. Connect with TLS."
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "reader_endpoint_address" {
  description = "Host name for reads, spread across replicas. Connect with TLS."
  value       = aws_elasticache_replication_group.this.reader_endpoint_address
}

output "port" {
  description = "Port to connect to."
  value       = aws_elasticache_replication_group.this.port
}

output "user_ids" {
  description = "Cache user for each client, keyed by the short name. The client connects with this as its user name."
  value       = { for key, user in aws_elasticache_user.this : key => user.user_id }
}

output "connect_policy_json" {
  description = "IAM policy for each client, keyed by the short name. It lets a role connect as that one user. Attach it to the client's workload role."
  value       = { for key, document in data.aws_iam_policy_document.connect : key => document.json }
}
