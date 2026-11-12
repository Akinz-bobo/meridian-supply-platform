output "table_name" {
  description = "Name of the table."
  value       = aws_dynamodb_table.this.name
}

output "table_arn" {
  description = "ARN of the table."
  value       = aws_dynamodb_table.this.arn
}

output "stream_arn" {
  description = "ARN of the change stream. Null when the table has no stream."
  value       = var.stream_view_type == null ? null : aws_dynamodb_table.this.stream_arn
}

output "read_policy_json" {
  description = "IAM policy that lets a role read items, by key or through an index. Scans are not included. Attach it to a workload role."
  value       = data.aws_iam_policy_document.read.json
}

output "write_policy_json" {
  description = "IAM policy that lets a role read and write items. It cannot change or delete the table. Attach it to a workload role."
  value       = data.aws_iam_policy_document.write.json
}

output "stream_policy_json" {
  description = "IAM policy that lets a role consume the table's change stream. Attach it to the role of a stream consumer."
  value       = data.aws_iam_policy_document.stream.json
}
