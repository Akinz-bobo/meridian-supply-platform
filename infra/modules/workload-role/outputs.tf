output "role_arn" {
  description = "ARN of the role. Give it to the task definition, function, pod identity association or state machine."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Name of the role, for attaching further policies from a service's own layer."
  value       = aws_iam_role.this.name
}

output "instance_profile_name" {
  description = "Name of the instance profile. Null unless the workload is ec2."
  value       = one(aws_iam_instance_profile.this[*].name)
}

output "instance_profile_arn" {
  description = "ARN of the instance profile. Null unless the workload is ec2."
  value       = one(aws_iam_instance_profile.this[*].arn)
}
