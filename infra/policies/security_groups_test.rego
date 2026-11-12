package terraform.security_groups_test

import rego.v1

import data.lib.fixtures
import data.terraform.security_groups

ingress(after) := fixtures.create("aws_vpc_security_group_ingress_rule", "r", after)

test_allows_https_from_the_internet if {
	rc := ingress({"description": "Clients", "cidr_ipv4": "0.0.0.0/0", "ip_protocol": "tcp", "from_port": 443, "to_port": 443})
	count(security_groups.deny) == 0 with input as fixtures.plan("prod", [rc])
}

test_allows_a_database_port_from_another_group if {
	rc := ingress({
		"description": "From workloads",
		"referenced_security_group_id": "sg-1",
		"ip_protocol": "tcp",
		"from_port": 5432,
		"to_port": 5432,
	})
	count(security_groups.deny) == 0 with input as fixtures.plan("prod", [rc])
}

test_allows_a_database_port_from_a_private_range if {
	rc := ingress({"description": "VPC", "cidr_ipv4": "10.30.0.0/16", "ip_protocol": "tcp", "from_port": 5432, "to_port": 5432})
	count(security_groups.deny) == 0 with input as fixtures.plan("prod", [rc])
}

test_denies_postgresql_from_the_internet if {
	rc := ingress({"description": "Oops", "cidr_ipv4": "0.0.0.0/0", "ip_protocol": "tcp", "from_port": 5432, "to_port": 5432})
	messages := security_groups.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-SG-1")
}

test_denies_redis_from_the_internet_over_ipv6 if {
	rc := ingress({"description": "Oops", "cidr_ipv6": "::/0", "ip_protocol": "tcp", "from_port": 6379, "to_port": 6379})
	messages := security_groups.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-SG-1")
}

test_denies_a_range_that_includes_a_web_port if {
	rc := ingress({"description": "Wide", "cidr_ipv4": "0.0.0.0/0", "ip_protocol": "tcp", "from_port": 0, "to_port": 65535})
	messages := security_groups.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-SG-1")
}

test_denies_all_protocols_from_the_internet if {
	rc := ingress({"description": "Everything", "cidr_ipv4": "0.0.0.0/0", "ip_protocol": "-1"})
	messages := security_groups.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-SG-1")
}

test_denies_ssh_from_the_internet_in_the_older_rule_resource if {
	rc := fixtures.create("aws_security_group_rule", "r", {
		"description": "SSH",
		"type": "ingress",
		"cidr_blocks": ["0.0.0.0/0"],
		"protocol": "tcp",
		"from_port": 22,
		"to_port": 22,
	})
	messages := security_groups.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-SG-1")
}

test_denies_an_inline_rule_open_to_the_internet if {
	rc := fixtures.create("aws_security_group", "g", {
		"name": "meridian-prod-x",
		"ingress": [{"cidr_blocks": ["0.0.0.0/0"], "protocol": "tcp", "from_port": 3306, "to_port": 3306}],
	})
	messages := security_groups.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-SG-1")
}

test_ignores_egress_to_the_internet if {
	rc := fixtures.create("aws_vpc_security_group_egress_rule", "r", {
		"description": "HTTPS out",
		"cidr_ipv4": "0.0.0.0/0",
		"ip_protocol": "tcp",
		"from_port": 443,
		"to_port": 443,
	})
	count(security_groups.deny) == 0 with input as fixtures.plan("prod", [rc])
}

test_denies_a_rule_without_a_description if {
	rc := ingress({"referenced_security_group_id": "sg-1", "ip_protocol": "tcp", "from_port": 8080, "to_port": 8080})
	messages := security_groups.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-SG-2")
}
