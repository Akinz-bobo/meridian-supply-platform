# Builders for plan fragments, used by the policy tests.
package lib.fixtures

import rego.v1

good_tags := {
	"Project": "meridian",
	"Environment": "prod",
	"Component": "inventory",
	"ManagedBy": "terraform",
}

# A plan for the given environment containing the given resource changes.
plan(environment, changes) := {
	"variables": {
		"project": {"value": "meridian"},
		"environment": {"value": environment},
		"aws_region": {"value": "eu-west-1"},
	},
	"resource_changes": changes,
}

# One resource change.
change(type, name, actions, after) := {
	"address": sprintf("%s.%s", [type, name]),
	"type": type,
	"change": {"actions": actions, "after": after, "after_unknown": {}},
}

create(type, name, after) := change(type, name, ["create"], after)
