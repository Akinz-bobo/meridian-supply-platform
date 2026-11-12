package terraform.secrets_test

import rego.v1

import data.lib.fixtures
import data.terraform.secrets

test_allows_a_version_written_through_the_write_only_argument if {
	rc := fixtures.create("aws_secretsmanager_secret_version", "v", {
		"secret_string": null,
		"secret_string_wo_version": 1,
	})
	count(secrets.deny) == 0 with input as fixtures.plan("prod", [rc])
}

test_denies_a_secret_value_given_in_configuration if {
	rc := fixtures.create("aws_secretsmanager_secret_version", "v", {"secret_string": "hunter2"})
	messages := secrets.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-SECRET-1")
}

test_denies_a_secret_value_that_is_computed_at_apply if {
	rc := {
		"address": "aws_secretsmanager_secret_version.v",
		"type": "aws_secretsmanager_secret_version",
		"change": {"actions": ["create"], "after": {}, "after_unknown": {"secret_string": true}},
	}
	messages := secrets.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-SECRET-1")
}

test_denies_a_binary_secret_value if {
	rc := fixtures.create("aws_secretsmanager_secret_version", "v", {"secret_binary": "aGVsbG8="})
	messages := secrets.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-SECRET-1")
}

test_allows_a_plain_parameter if {
	rc := fixtures.create("aws_ssm_parameter", "p", {
		"name": "/meridian/prod/catalog/config/log-level",
		"type": "String",
		"value": "info",
	})
	count(secrets.deny) == 0 with input as fixtures.plan("prod", [rc])
}

test_denies_a_secure_parameter_with_a_stored_value if {
	rc := fixtures.create("aws_ssm_parameter", "p", {
		"name": "/meridian/prod/catalog/config/token",
		"type": "SecureString",
		"value": "abc",
	})
	messages := secrets.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-SECRET-2")
}

test_allows_a_secure_parameter_written_through_the_write_only_argument if {
	rc := fixtures.create("aws_ssm_parameter", "p", {
		"name": "/meridian/prod/catalog/config/token",
		"type": "SecureString",
		"value": null,
		"value_wo_version": 1,
	})
	count(secrets.deny) == 0 with input as fixtures.plan("prod", [rc])
}

test_denies_a_secret_that_can_be_deleted_immediately if {
	rc := fixtures.create("aws_secretsmanager_secret", "s", {
		"name": "/meridian/prod/catalog/secrets/token",
		"recovery_window_in_days": 0,
	})
	messages := secrets.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-SECRET-3")
}

test_allows_a_week_of_recovery if {
	rc := fixtures.create("aws_secretsmanager_secret", "s", {
		"name": "/meridian/prod/catalog/secrets/token",
		"recovery_window_in_days": 7,
	})
	count(secrets.deny) == 0 with input as fixtures.plan("prod", [rc])
}
