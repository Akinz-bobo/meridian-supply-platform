output "vpc_id" {
  description = "Identifier of the VPC."
  value       = aws_vpc.this.id
}

output "cidr_block" {
  description = "Address range of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "availability_zones" {
  description = "Zones the subnets are spread across, in address plan order."
  value       = var.availability_zones
}

output "public_subnet_ids" {
  description = "Identifiers of the public subnets, in zone order. For load balancers."
  value       = [for letter in keys(local.zones) : aws_subnet.public[letter].id]
}

output "private_subnet_ids" {
  description = "Identifiers of the private subnets, in zone order. For workloads."
  value       = [for letter in keys(local.zones) : aws_subnet.private[letter].id]
}

output "data_subnet_ids" {
  description = "Identifiers of the data subnets, in zone order. For databases and caches."
  value       = [for letter in keys(local.zones) : aws_subnet.data[letter].id]
}

output "private_subnet_cidr_blocks" {
  description = "Address ranges of the private subnets, in zone order."
  value       = [for letter in keys(local.zones) : local.private_cidrs[letter]]
}

output "data_subnet_cidr_blocks" {
  description = "Address ranges of the data subnets, in zone order."
  value       = [for letter in keys(local.zones) : local.data_cidrs[letter]]
}

output "public_route_table_id" {
  description = "Identifier of the route table shared by the public subnets."
  value       = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "Identifiers of the private route tables, one per zone. Gateway endpoints attach to these."
  value       = [for letter in keys(local.zones) : aws_route_table.private[letter].id]
}

output "data_route_table_id" {
  description = "Identifier of the route table shared by the data subnets. It has no route to the internet."
  value       = aws_route_table.data.id
}

output "nat_public_ips" {
  description = "Public addresses that outbound traffic from the private subnets appears to come from. Give these to a partner who allow-lists by address."
  value       = [for letter in keys(local.nat_zones) : aws_eip.nat[letter].public_ip]
}
