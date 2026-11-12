# Private paths from a VPC to AWS services.
#
# Gateway endpoints (S3 and DynamoDB) add routes to route tables and cost
# nothing. Interface endpoints put a network interface for a service in the
# given subnets, behind one security group that accepts HTTPS from the VPC.
#
# With these in place a workload reaches AWS APIs without leaving the AWS
# network.
#
# Every endpoint carries a policy. Without one an endpoint lets any
# principal reach any resource of the service, which makes it a way to copy
# data to a bucket or table in someone else's account. With it, only this
# account's principals can use the endpoint, and a gateway endpoint reaches
# only this account's resources.

data "aws_region" "current" {}

locals {
  service_prefix = "com.amazonaws.${data.aws_region.current.region}"
}

data "aws_iam_policy_document" "gateway" {
  for_each = var.gateway_services

  statement {
    sid       = "OnlyThisAccountsPrincipalsAndResources"
    actions   = ["${each.key}:*"]
    resources = ["*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalAccount"
      values   = [var.account_id]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      values   = [var.account_id]
    }
  }

  # Container image layers are served from a bucket that ECR owns. Without
  # this, pulling an image through the S3 endpoint fails.
  dynamic "statement" {
    for_each = each.key == "s3" ? [1] : []

    content {
      sid       = "ReadContainerImageLayers"
      actions   = ["s3:GetObject"]
      resources = ["arn:aws:s3:::prod-${data.aws_region.current.region}-starport-layer-bucket/*"]

      principals {
        type        = "*"
        identifiers = ["*"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:PrincipalAccount"
        values   = [var.account_id]
      }
    }
  }
}

# An interface endpoint fronts an AWS API, and the resources behind some of
# those APIs belong to AWS, so only the caller is restricted.
data "aws_iam_policy_document" "interface" {
  statement {
    sid       = "OnlyThisAccountsPrincipals"
    actions   = ["*"]
    resources = ["*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalAccount"
      values   = [var.account_id]
    }
  }
}

resource "aws_vpc_endpoint" "gateway" {
  for_each = var.gateway_services

  vpc_id            = var.vpc_id
  service_name      = "${local.service_prefix}.${each.key}"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.route_table_ids
  policy            = data.aws_iam_policy_document.gateway[each.key].json

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
  policy              = data.aws_iam_policy_document.interface.json

  # Dots are not allowed in the names we use, and some services have them
  # (ecr.api, ecr.dkr).
  tags = merge(var.tags, { Name = "${var.name}-${replace(each.key, ".", "-")}" })
}
