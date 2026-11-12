output "stream_name" {
  description = "Name of the stream."
  value       = aws_kinesis_stream.this.name
}

output "stream_arn" {
  description = "ARN of the stream."
  value       = aws_kinesis_stream.this.arn
}

output "produce_policy_json" {
  description = "IAM policy that lets a role write records to the stream. It cannot read them. Attach it to a producer's workload role."
  value       = data.aws_iam_policy_document.produce.json
}

output "consume_policy_json" {
  description = "IAM policy that lets a role read records from the stream. It cannot write to it. Attach it to a consumer's workload role."
  value       = data.aws_iam_policy_document.consume.json
}
