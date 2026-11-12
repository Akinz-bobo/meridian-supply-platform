output "queue_name" {
  description = "Name of the queue."
  value       = aws_sqs_queue.this.name
}

output "queue_url" {
  description = "URL of the queue. The consumer receives from it."
  value       = aws_sqs_queue.this.url
}

output "queue_arn" {
  description = "ARN of the queue."
  value       = aws_sqs_queue.this.arn
}

output "dead_letter_queue_url" {
  description = "URL of the dead-letter queue, for inspecting and redriving failed messages."
  value       = aws_sqs_queue.dead_letter.url
}

output "dead_letter_queue_arn" {
  description = "ARN of the dead-letter queue."
  value       = aws_sqs_queue.dead_letter.arn
}

output "rule_name" {
  description = "Name of the rule on the bus that feeds the queue."
  value       = aws_cloudwatch_event_rule.this.name
}

output "alarm_name" {
  description = "Name of the alarm that fires when the dead-letter queue is not empty."
  value       = aws_cloudwatch_metric_alarm.dead_letter.alarm_name
}

output "consume_policy_json" {
  description = "IAM policy that lets a role receive and acknowledge messages from the queue. It cannot send to it, purge it or read the dead-letter queue. Attach it to the consumer's workload role."
  value       = data.aws_iam_policy_document.consume.json
}
