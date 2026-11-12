# Private paths from a VPC to AWS services.
#
# Gateway endpoints (S3 and DynamoDB) add routes to route tables and cost
# nothing. Interface endpoints put a network interface for a service in the
# given subnets, behind one security group that accepts HTTPS from the VPC.
#
# With these in place a workload reaches AWS APIs without leaving the AWS
# network, and the data tier can reach S3 and DynamoDB with no internet
# route at all.

data "aws_region" "current" {}

locals {
  service_prefix = "com.amazonaws.${data.aws_region.current.region}"
}

resource "aws_vpc_endpoint" "gateway" {
  for_each = var.gateway_services

  vpc_id            = var.vpc_id
  service_name      = "${local.service_prefix}.${each.key}"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.route_table_ids

  tags = merge(var.tags, { Name = "${var.name}-${each.key}" })
}

resource "aws_security_group" "interface" {
  count = length(var.interface_services) > 0 ? 1 : 0

  name        = "${var.name}-endpoints"
  description = "HTTPS from inside the VPC to interface endpoints for AWS services."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-endpoints" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "interface_https" {
  count = length(var.interface_services) > 0 ? 1 : 0

  security_group_id = aws_security_group.interface[0].id
  description       = "HTTPS from the VPC"
  cidr_ipv4         = var.vpc_cidr_block
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443

  tags = var.tags
}

resource "aws_vpc_endpoint" "interface" {
  for_each = var.interface_services

  vpc_id              = var.vpc_id
  service_name        = "${local.service_prefix}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.interface[0].id]
  private_dns_enabled = true

  # Dots are not allowed in the names we use, and some services have them
  # (ecr.api, ecr.dkr).
  tags = merge(var.tags, { Name = "${var.name}-${replace(each.key, ".", "-")}" })
}
