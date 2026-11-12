output "gateway_endpoint_ids" {
  description = "Identifiers of the gateway endpoints, keyed by service."
  value       = { for service, endpoint in aws_vpc_endpoint.gateway : service => endpoint.id }
}

output "interface_endpoint_ids" {
  description = "Identifiers of the interface endpoints, keyed by service."
  value       = { for service, endpoint in aws_vpc_endpoint.interface : service => endpoint.id }
}

output "security_group_id" {
  description = "Identifier of the security group in front of the interface endpoints. Null when there are no interface endpoints."
  value       = one(aws_security_group.interface[*].id)
}

output "s3_prefix_list_id" {
  description = "Prefix list of the S3 gateway endpoint, for security group rules that allow traffic to S3 only. Null when S3 is not a gateway service."
  value       = try(aws_vpc_endpoint.gateway["s3"].prefix_list_id, null)
}

output "dynamodb_prefix_list_id" {
  description = "Prefix list of the DynamoDB gateway endpoint, for security group rules that allow traffic to DynamoDB only. Null when DynamoDB is not a gateway service."
  value       = try(aws_vpc_endpoint.gateway["dynamodb"].prefix_list_id, null)
}
