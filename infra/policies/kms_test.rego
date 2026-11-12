package terraform.kms_test

import rego.v1

import data.lib.fixtures
import data.terraform.kms

test_allows_a_rotating_key_with_a_long_deletion_window if {
	rc := fixtures.create("aws_kms_key", "k", {"enable_key_rotation": true, "deletion_window_in_days": 30})
	count(kms.deny) == 0 with input as fixtures.plan("prod", [rc])
}

test_denies_a_key_with_rotation_off if {
	rc := fixtures.create("aws_kms_key", "k", {"enable_key_rotation": false, "deletion_window_in_days": 30})
	messages := kms.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-KMS-1")
}

test_denies_a_key_with_rotation_left_out if {
	rc := fixtures.create("aws_kms_key", "k", {"deletion_window_in_days": 30})
	messages := kms.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-KMS-1")
}

test_denies_a_one_week_deletion_window if {
	rc := fixtures.create("aws_kms_key", "k", {"enable_key_rotation": true, "deletion_window_in_days": 7})
	messages := kms.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-KMS-2")
}

test_allows_exactly_the_minimum_window if {
	rc := fixtures.create("aws_kms_key", "k", {"enable_key_rotation": true, "deletion_window_in_days": 14})
	count(kms.deny) == 0 with input as fixtures.plan("prod", [rc])
}
