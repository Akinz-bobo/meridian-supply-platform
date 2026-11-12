# Plan-only tests against a mocked provider. No AWS account or emulator is
# needed. They pin the shape of the chain: internet, load balancer,
# application, data.

mock_provider "aws" {}

variables {
  name           = "meridian-prod-network"
  vpc_id         = "vpc-0123456789abcdef0"
  vpc_cidr_block = "10.30.0.0/16"
  tags = {
    Project = "meridian"
  }
}

run "creates_one_group_per_tier" {
  command = plan

  assert {
    condition     = aws_security_group.load_balancer.name == "meridian-prod-network-lb"
    error_message = "The load balancer group is named <name>-lb."
  }

  assert {
    condition     = aws_security_group.application.name == "meridian-prod-network-app"
    error_message = "The application group is named <name>-app."
  }

  assert {
    condition     = aws_security_group.data.name == "meridian-prod-network-data"
    error_message = "The data group is named <name>-data."
  }
}

run "only_the_load_balancer_accepts_traffic_from_an_address_range" {
  command = plan

  assert {
    condition     = [for rule in aws_vpc_security_group_ingress_rule.load_balancer_from_clients : rule.from_port] == [443]
    error_message = "By default clients reach the load balancer on 443 only."
  }

  # Every ingress rule on the application and data groups names a group.
  assert {
    condition = alltrue(concat(
      [for rule in aws_vpc_security_group_ingress_rule.application_from_load_balancer : rule.cidr_ipv4 == null],
      [aws_vpc_security_group_ingress_rule.application_from_application.cidr_ipv4 == null],
      [for rule in aws_vpc_security_group_ingress_rule.data_from_application : rule.cidr_ipv4 == null],
      [for rule in aws_vpc_security_group_ingress_rule.data_from_data : rule.cidr_ipv4 == null],
    ))
    error_message = "Ingress to the application and data groups must be by group reference, never by address range."
  }
}

run "opens_only_the_data_ports_to_the_data_tier" {
  command = plan

  assert {
    condition     = { for key, rule in aws_vpc_security_group_ingress_rule.data_from_application : key => rule.from_port } == { postgresql = 5432, redis = 6379 }
    error_message = "The data group accepts PostgreSQL and Redis from workloads by default."
  }

  assert {
    condition     = alltrue([for rule in aws_vpc_security_group_ingress_rule.data_from_application : rule.from_port == rule.to_port])
    error_message = "Each data rule opens exactly one port."
  }
}

run "lets_workloads_out_on_https_and_dns_only" {
  command = plan

  assert {
    condition     = aws_vpc_security_group_egress_rule.application_to_https.from_port == 443 && aws_vpc_security_group_egress_rule.application_to_https.to_port == 443
    error_message = "The only rule from workloads to the internet is HTTPS."
  }

  assert {
    condition     = alltrue([for rule in aws_vpc_security_group_egress_rule.application_to_dns : rule.cidr_ipv4 == "10.30.0.0/16" && rule.from_port == 53])
    error_message = "DNS is allowed to the VPC range only."
  }
}

run "describes_every_rule" {
  command = plan

  assert {
    condition = alltrue(concat(
      [for rule in aws_vpc_security_group_ingress_rule.load_balancer_from_clients : length(rule.description) > 0],
      [for rule in aws_vpc_security_group_egress_rule.application_to_data : length(rule.description) > 0],
      [for rule in aws_vpc_security_group_ingress_rule.data_from_data : length(rule.description) > 0],
    ))
    error_message = "A rule without a description cannot be reviewed."
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.application_to_data["postgresql"].description == "To postgresql on port 5432"
    error_message = "The description of a data rule names the store and the port."
  }
}

run "can_restrict_clients_to_known_ranges" {
  command = plan

  variables {
    load_balancer_ports         = [80, 443]
    load_balancer_ingress_cidrs = ["198.51.100.0/24", "203.0.113.0/24"]
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.load_balancer_from_clients) == 4
    error_message = "Two ports and two ranges give four rules."
  }

  assert {
    condition     = !contains([for rule in aws_vpc_security_group_ingress_rule.load_balancer_from_clients : rule.cidr_ipv4], "0.0.0.0/0")
    error_message = "With explicit ranges, the internet must not be allowed."
  }
}

run "adds_a_rule_pair_per_application_port" {
  command = plan

  variables {
    app_ports = [8080, 9090]
  }

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.load_balancer_to_application) == 2 && length(aws_vpc_security_group_ingress_rule.application_from_load_balancer) == 2
    error_message = "Each application port needs an egress rule on the load balancer group and an ingress rule on the application group."
  }
}

run "rejects_a_database_port_on_the_load_balancer" {
  command = plan

  variables {
    load_balancer_ports = [443, 5432]
  }

  expect_failures = [var.load_balancer_ports]
}

run "rejects_plain_http_alone" {
  command = plan

  variables {
    load_balancer_ports = [80]
  }

  expect_failures = [var.load_balancer_ports]
}

run "rejects_a_privileged_application_port" {
  command = plan

  variables {
    app_ports = [80]
  }

  expect_failures = [var.app_ports]
}

run "rejects_an_invalid_client_range" {
  command = plan

  variables {
    load_balancer_ingress_cidrs = ["everywhere"]
  }

  expect_failures = [var.load_balancer_ingress_cidrs]
}
