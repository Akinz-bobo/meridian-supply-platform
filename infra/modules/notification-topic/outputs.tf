output "topic_arn" {
  description = "ARN of the topic. Use it as an alarm action or a rule target."
  value       = aws_sns_topic.this.arn
}

output "topic_name" {
  description = "Name of the topic."
  value       = aws_sns_topic.this.name
}

output "publish_policy_json" {
  description = "IAM policy that lets a role publish to the topic. Attach it to a workload role."
  value       = data.aws_iam_policy_document.publish.json
}
