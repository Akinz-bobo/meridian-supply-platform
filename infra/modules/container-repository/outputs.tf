output "repository_name" {
  description = "Name of the repository."
  value       = aws_ecr_repository.this.name
}

output "repository_url" {
  description = "Address to push to and pull from, without a tag."
  value       = aws_ecr_repository.this.repository_url
}

output "repository_arn" {
  description = "ARN of the repository."
  value       = aws_ecr_repository.this.arn
}

output "pull_policy_json" {
  description = "IAM policy that lets a role pull images from this repository. Attach it to a task execution role or a node role."
  value       = data.aws_iam_policy_document.pull.json
}

output "push_policy_json" {
  description = "IAM policy that lets a role push images to this repository. It cannot delete an image or change the repository. Attach it to the role that builds."
  value       = data.aws_iam_policy_document.push.json
}
