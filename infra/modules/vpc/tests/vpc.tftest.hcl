# Plan-only tests against a mocked provider. No AWS account or emulator is
# needed. They pin the address plan and the isolation of the data tier.

mock_provider "aws" {}

variables {
  name               = "meridian-prod-network"
  cidr_block         = "10.30.0.0/16"
  availability_zones = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  tags = {
    Project = "meridian"
  }
}

run "lays_out_subnets_according_to_the_address_plan" {
  command = plan

  assert {
    condition     = [for letter in ["a", "b", "c"] : aws_subnet.public[letter].cidr_block] == ["10.30.0.0/24", "10.30.1.0/24", "10.30.2.0/24"]
    error_message = "Public subnets must be x.x.0.0/24, x.x.1.0/24 and x.x.2.0/24."
  }

  assert {
    condition     = [for letter in ["a", "b", "c"] : aws_subnet.private[letter].cidr_block] == ["10.30.32.0/19", "10.30.64.0/19", "10.30.96.0/19"]
    error_message = "Private subnets must be x.x.32.0/19, x.x.64.0/19 and x.x.96.0/19."
  }

  assert {
    condition     = [for letter in ["a", "b", "c"] : aws_subnet.data[letter].cidr_block] == ["10.30.160.0/24", "10.30.161.0/24", "10.30.162.0/24"]
    error_message = "Data subnets must be x.x.160.0/24, x.x.161.0/24 and x.x.162.0/24."
  }
}

run "puts_each_subnet_in_its_own_zone" {
  command = plan

  assert {
    condition     = aws_subnet.private["b"].availability_zone == "eu-west-1b"
    error_message = "The subnet keyed b must be in the zone ending in b."
  }

  assert {
    condition     = length(aws_subnet.public) == 3 && length(aws_subnet.private) == 3 && length(aws_subnet.data) == 3
    error_message = "Each tier must have one subnet per zone."
  }
}

run "names_resources_after_tier_and_zone" {
  command = plan

  assert {
    condition     = aws_subnet.data["c"].tags["Name"] == "meridian-prod-network-data-c"
    error_message = "A subnet is named <name>-<tier>-<zone letter>."
  }

  assert {
    condition     = aws_subnet.data["c"].tags["Tier"] == "data"
    error_message = "A subnet carries its tier as a tag."
  }

  assert {
    condition     = aws_vpc.this.tags["Project"] == "meridian"
    error_message = "The caller's tags must reach the VPC."
  }
}

run "gives_the_data_tier_no_route_to_the_internet" {
  command = plan

  # The only routes the module creates are the public default route and one
  # NAT route per private table. Neither targets the data route table.
  assert {
    condition     = length(aws_route.private_nat) == 3
    error_message = "There must be exactly one NAT route per private route table."
  }

  assert {
    condition     = length(aws_route_table_association.data) == 3
    error_message = "Every data subnet must be associated with the data route table."
  }

  assert {
    condition     = aws_network_acl_rule.data_out_to_vpc.cidr_block == "10.30.0.0/16"
    error_message = "The data tier may only send traffic to the VPC range."
  }
}

run "only_lets_the_private_and_data_tiers_into_the_data_tier" {
  command = plan

  assert {
    condition = toset(concat(
      [for rule in aws_network_acl_rule.data_in_from_private : rule.cidr_block],
      [for rule in aws_network_acl_rule.data_in_from_data : rule.cidr_block],
      )) == toset([
      "10.30.32.0/19", "10.30.64.0/19", "10.30.96.0/19",
      "10.30.160.0/24", "10.30.161.0/24", "10.30.162.0/24",
    ])
    error_message = "Inbound rules on the data network ACL must list the private and data subnets and nothing else."
  }
}

run "does_not_hand_out_public_addresses_by_default" {
  command = plan

  assert {
    condition     = alltrue([for subnet in aws_subnet.public : subnet.map_public_ip_on_launch == false])
    error_message = "Public subnets must not assign public addresses on launch."
  }
}

run "creates_a_nat_gateway_per_zone_by_default" {
  command = plan

  assert {
    condition     = length(aws_nat_gateway.this) == 3
    error_message = "The default is one NAT gateway per zone."
  }
}

run "can_share_one_nat_gateway_to_save_cost" {
  command = plan

  variables {
    single_nat_gateway = true
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 1 && contains(keys(aws_nat_gateway.this), "a")
    error_message = "With single_nat_gateway there is one gateway, in the first zone."
  }

  assert {
    condition     = length(aws_route.private_nat) == 3
    error_message = "Every private route table still needs a NAT route."
  }
}

run "works_with_two_zones" {
  command = plan

  variables {
    availability_zones = ["eu-west-1a", "eu-west-1b"]
  }

  assert {
    condition     = length(aws_subnet.private) == 2
    error_message = "Two zones give two subnets per tier."
  }
}

run "adds_discovery_tags_to_subnets" {
  command = plan

  variables {
    private_subnet_tags = { "kubernetes.io/role/internal-elb" = "1" }
  }

  assert {
    condition     = aws_subnet.private["a"].tags["kubernetes.io/role/internal-elb"] == "1"
    error_message = "Extra private subnet tags must be applied."
  }

  assert {
    condition     = !contains(keys(aws_subnet.public["a"].tags), "kubernetes.io/role/internal-elb")
    error_message = "Private subnet tags must not leak onto public subnets."
  }
}

run "rejects_a_range_that_is_not_a_16" {
  command = plan

  variables {
    cidr_block = "10.30.0.0/20"
  }

  expect_failures = [var.cidr_block]
}

run "rejects_a_range_outside_the_private_plan" {
  command = plan

  variables {
    cidr_block = "172.16.0.0/16"
  }

  expect_failures = [var.cidr_block]
}

run "rejects_a_single_zone" {
  command = plan

  variables {
    availability_zones = ["eu-west-1a"]
  }

  expect_failures = [var.availability_zones]
}

run "rejects_a_repeated_zone" {
  command = plan

  variables {
    availability_zones = ["eu-west-1a", "eu-west-1a", "eu-west-1b"]
  }

  expect_failures = [var.availability_zones]
}
