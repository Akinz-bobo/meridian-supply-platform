output "bus_name" {
  description = "Name of the bus. Producers put events on it, and consumer rules attach to it."
  value       = aws_cloudwatch_event_bus.this.name
}

output "bus_arn" {
  description = "ARN of the bus."
  value       = aws_cloudwatch_event_bus.this.arn
}

output "archive_arn" {
  description = "ARN of the archive, for starting a replay."
  value       = aws_cloudwatch_event_archive.this.arn
}

output "log_group_name" {
  description = "Log group that holds a readable copy of every event."
  value       = aws_cloudwatch_log_group.events.name
}

output "publish_policy_json" {
  description = "IAM policy for each publisher, keyed by its name. It lets a role put events on the bus under that service's source and no other. Attach it to the service's workload role."
  value       = { for publisher, document in data.aws_iam_policy_document.publish : publisher => document.json }
}
