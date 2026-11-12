# POL-SG: security group rules.
#
# Only web ports may be open to the whole internet, and every rule says
# what it is for.
package terraform.security_groups

import rego.v1

import data.lib.plan

world := {"0.0.0.0/0", "::/0"}

# Ports a load balancer may expose to the internet.
web_ports := {80, 443}

# A rule normalised to: direction, sources, protocol, port range.
rules contains rule if {
	some rc in plan.changing
	rc.type == "aws_vpc_security_group_ingress_rule"
	after := rc.change.after
	rule := {
		"address": rc.address,
		"cidrs": {cidr | some key in ["cidr_ipv4", "cidr_ipv6"]; cidr := after[key]; is_string(cidr)},
		"protocol": after.ip_protocol,
		"from": object.get(after, "from_port", null),
		"to": object.get(after, "to_port", null),
	}
}

rules contains rule if {
	some rc in plan.changing
	rc.type == "aws_security_group_rule"
	after := rc.change.after
	after.type == "ingress"
	rule := {
		"address": rc.address,
		"cidrs": {cidr |
			some key in ["cidr_blocks", "ipv6_cidr_blocks"]
			some cidr in object.get(after, key, [])
		},
		"protocol": after.protocol,
		"from": after.from_port,
		"to": after.to_port,
	}
}

rules contains rule if {
	some rc in plan.changing
	rc.type == "aws_security_group"
	some index, ingress in object.get(rc.change.after, "ingress", [])
	rule := {
		"address": sprintf("%s ingress %d", [rc.address, index]),
		"cidrs": {cidr |
			some key in ["cidr_blocks", "ipv6_cidr_blocks"]
			some cidr in object.get(ingress, key, [])
		},
		"protocol": ingress.protocol,
		"from": ingress.from_port,
		"to": ingress.to_port,
	}
}

open_to_world(rule) if count(rule.cidrs & world) > 0

single_web_port(rule) if {
	rule.protocol == "tcp"
	rule.from == rule.to
	rule.from in web_ports
}

deny contains msg if {
	some rule in rules
	open_to_world(rule)
	not single_web_port(rule)
	msg := sprintf(
		"POL-SG-1: %s accepts %s ports %v to %v from the internet. Only TCP 80 and 443 may be open to the world",
		[rule.address, rule.protocol, rule.from, rule.to],
	)
}

rule_types := {
	"aws_security_group_rule",
	"aws_vpc_security_group_egress_rule",
	"aws_vpc_security_group_ingress_rule",
}

deny contains msg if {
	some rc in plan.changing
	rc.type in rule_types
	object.get(rc.change.after, "description", "") in {"", null}
	msg := sprintf("POL-SG-2: %s has no description. Say what the rule is for", [rc.address])
}
