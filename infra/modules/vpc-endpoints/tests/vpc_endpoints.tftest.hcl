# Plan-only tests against a mocked provider. No AWS account or emulator is
# needed.

mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      region = "eu-west-1"
    }
  }
}

variables {
  name            = "meridian-prod-network"
  vpc_id          = "vpc-0123456789abcdef0"
  vpc_cidr_block  = "10.30.0.0/16"
  route_table_ids = ["rtb-private-a", "rtb-private-b", "rtb-private-c", "rtb-data"]
  subnet_ids      = ["subnet-private-a", "subnet-private-b", "subnet-private-c"]
  tags = {
    Project = "meridian"
  }
}

run "creates_gateway_endpoints_for_s3_and_dynamodb" {
  command = plan

  assert {
    condition     = toset(keys(aws_vpc_endpoint.gateway)) == toset(["s3", "dynamodb"])
    error_message = "S3 and DynamoDB get gateway endpoints by default."
  }

  assert {
    condition     = aws_vpc_endpoint.gateway["s3"].service_name == "com.amazonaws.eu-west-1.s3"
    error_message = "The service name is built from the provider's region."
  }

  assert {
    condition     = aws_vpc_endpoint.gateway["dynamodb"].vpc_endpoint_type == "Gateway"
    error_message = "DynamoDB must use a gateway endpoint."
  }
}

run "attaches_gateway_endpoints_to_every_given_route_table" {
  command = plan

  assert {
    condition     = length(aws_vpc_endpoint.gateway["s3"].route_table_ids) == 4
    error_message = "The S3 endpoint must be routed from every private and data route table."
  }
}

run "creates_interface_endpoints_with_private_dns" {
  command = plan

  assert {
    condition     = alltrue([for endpoint in aws_vpc_endpoint.interface : endpoint.private_dns_enabled])
    error_message = "Private DNS must be on, or SDKs keep resolving the public endpoint."
  }

  assert {
    condition     = alltrue([for endpoint in aws_vpc_endpoint.interface : length(endpoint.subnet_ids) == 3])
    error_message = "Each interface endpoint needs an interface in every zone."
  }

  assert {
    condition     = contains(keys(aws_vpc_endpoint.interface), "secretsmanager")
    error_message = "Secrets Manager is in the default set."
  }
}

run "names_endpoints_without_dots" {
  command = plan

  assert {
    condition     = aws_vpc_endpoint.interface["ecr.api"].tags["Name"] == "meridian-prod-network-ecr-api"
    error_message = "A dot in a service name becomes a hyphen in the endpoint's name."
  }
}

run "only_accepts_https_from_the_vpc" {
  command = plan

  assert {
    condition     = aws_vpc_security_group_ingress_rule.interface_https[0].cidr_ipv4 == "10.30.0.0/16"
    error_message = "The endpoint security group must accept traffic from the VPC range only."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.interface_https[0].from_port == 443 && aws_vpc_security_group_ingress_rule.interface_https[0].to_port == 443
    error_message = "The endpoint security group must accept port 443 only."
  }
}

run "creates_no_security_group_without_interface_endpoints" {
  command = plan

  variables {
    interface_services = []
  }

  assert {
    condition     = length(aws_security_group.interface) == 0 && length(aws_vpc_endpoint.interface) == 0
    error_message = "With no interface endpoints there is nothing for a security group to protect."
  }

  assert {
    condition     = output.security_group_id == null
    error_message = "The security group output must be null when no group exists."
  }
}

run "rejects_a_gateway_service_that_does_not_exist" {
  command = plan

  variables {
    gateway_services = ["s3", "sqs"]
  }

  expect_failures = [var.gateway_services]
}

run "rejects_s3_as_an_interface_endpoint" {
  command = plan

  variables {
    interface_services = ["s3", "logs"]
  }

  expect_failures = [var.interface_services]
}

run "rejects_a_full_service_name" {
  command = plan

  variables {
    interface_services = ["com.amazonaws.eu-west-1.SQS"]
  }

  expect_failures = [var.interface_services]
}
