output "bucket_name" {
  description = "Name of the bucket."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the bucket."
  value       = aws_s3_bucket.this.arn
}

output "read_policy_json" {
  description = "IAM policy that lets a role list the bucket and read and decrypt its objects. Attach it to a workload role."
  value       = data.aws_iam_policy_document.read.json
}

output "write_policy_json" {
  description = "IAM policy that lets a role read, write and delete current objects. It cannot delete versions or change the bucket. Attach it to a workload role."
  value       = data.aws_iam_policy_document.write.json
}
