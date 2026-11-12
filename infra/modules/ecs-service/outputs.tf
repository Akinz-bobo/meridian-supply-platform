output "service_name" {
  description = "Name of the ECS service."
  value       = aws_ecs_service.this.name
}

output "task_definition_arn" {
  description = "ARN of the task definition revision the service runs."
  value       = aws_ecs_task_definition.this.arn
}

output "security_group_id" {
  description = "Identifier of the service's own security group. Another service that calls this one adds a rule that refers to it."
  value       = aws_security_group.this.id
}

output "target_group_arn" {
  description = "ARN of the service's target group."
  value       = aws_lb_target_group.this.arn
}

output "log_group_name" {
  description = "Log group that receives the container's output."
  value       = aws_cloudwatch_log_group.this.name
}
