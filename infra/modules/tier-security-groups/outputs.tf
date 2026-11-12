output "load_balancer_security_group_id" {
  description = "Identifier of the group for load balancers."
  value       = aws_security_group.load_balancer.id
}

output "application_security_group_id" {
  description = "Identifier of the group for workloads: ECS tasks, EKS nodes, Lambda functions and EC2 instances."
  value       = aws_security_group.application.id
}

output "data_security_group_id" {
  description = "Identifier of the group for databases and caches."
  value       = aws_security_group.data.id
}
