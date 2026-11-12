output "cluster_name" {
  description = "Name of the cluster."
  value       = aws_ecs_cluster.this.name
}

output "cluster_arn" {
  description = "ARN of the cluster. A service is created in it."
  value       = aws_ecs_cluster.this.arn
}

output "exec_log_group_name" {
  description = "Log group that records shell sessions in containers."
  value       = aws_cloudwatch_log_group.exec.name
}
