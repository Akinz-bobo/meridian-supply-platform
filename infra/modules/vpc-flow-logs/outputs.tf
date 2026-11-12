output "log_group_name" {
  description = "Name of the log group that receives the flow logs."
  value       = aws_cloudwatch_log_group.this.name
}

output "log_group_arn" {
  description = "ARN of the log group that receives the flow logs."
  value       = aws_cloudwatch_log_group.this.arn
}

output "flow_log_id" {
  description = "Identifier of the flow log."
  value       = aws_flow_log.this.id
}

output "role_arn" {
  description = "ARN of the role the flow logs service uses to write to the log group."
  value       = aws_iam_role.this.arn
}
