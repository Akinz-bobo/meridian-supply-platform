output "policy_arn" {
  description = "ARN of the boundary policy. Set it as permissions_boundary on every workload role."

  # Built from its parts and not read from the resource, so that the value
  # is known at plan time. Policies that mention the boundary can then be
  # rendered, reviewed and policy checked before anything is applied. The
  # dependency keeps the ordering: nothing uses the ARN before the policy
  # exists.
  value      = "arn:aws:iam::${var.account_id}:policy/${var.name}"
  depends_on = [aws_iam_policy.this]
}

output "policy_name" {
  description = "Name of the boundary policy."
  value       = aws_iam_policy.this.name
}
