package terraform.logging_test

import rego.v1

import data.lib.fixtures
import data.terraform.logging

test_allows_a_log_group_with_ninety_days if {
	rc := fixtures.create("aws_cloudwatch_log_group", "g", {"name": "/meridian/prod/x", "retention_in_days": 90, "kms_key_id": "arn:aws:kms:eu-west-1:333333333333:key/k"})
	count(logging.deny) == 0 with input as fixtures.plan("prod", [rc])
}

test_allows_exactly_the_minimum if {
	rc := fixtures.create("aws_cloudwatch_log_group", "g", {"name": "/meridian/prod/x", "retention_in_days": 30, "kms_key_id": "arn:aws:kms:eu-west-1:333333333333:key/k"})
	count(logging.deny) == 0 with input as fixtures.plan("prod", [rc])
}

test_denies_a_log_group_that_never_expires if {
	rc := fixtures.create("aws_cloudwatch_log_group", "g", {"name": "/meridian/prod/x", "retention_in_days": 0})
	messages := logging.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-LOG-1")
}

test_denies_a_log_group_with_retention_left_out if {
	rc := fixtures.create("aws_cloudwatch_log_group", "g", {"name": "/meridian/prod/x"})
	messages := logging.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-LOG-1")
}

test_denies_a_week_of_retention if {
	rc := fixtures.create("aws_cloudwatch_log_group", "g", {"name": "/meridian/prod/x", "retention_in_days": 7})
	messages := logging.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-LOG-2")
}

test_ignores_other_resource_types if {
	rc := fixtures.create("aws_sqs_queue", "q", {"name": "meridian-prod-x"})
	count(logging.deny) == 0 with input as fixtures.plan("prod", [rc])
}

test_denies_a_log_group_without_a_customer_managed_key if {
	rc := fixtures.create("aws_cloudwatch_log_group", "g", {"name": "/meridian/prod/x", "retention_in_days": 90})
	messages := logging.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-LOG-3")
}

test_allows_a_log_group_whose_key_is_not_known_until_apply if {
	rc := {
		"address": "aws_cloudwatch_log_group.g",
		"type": "aws_cloudwatch_log_group",
		"change": {
			"actions": ["create"],
			"after": {"name": "/meridian/prod/x", "retention_in_days": 90},
			"after_unknown": {"kms_key_id": true},
		},
	}
	count(logging.deny) == 0 with input as fixtures.plan("prod", [rc])
}
