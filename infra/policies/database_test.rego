package terraform.database_test

import rego.v1

import data.lib.fixtures
import data.terraform.database

good := {
	"identifier": "meridian-prod-catalog-db",
	"publicly_accessible": false,
	"storage_encrypted": true,
	"manage_master_user_password": true,
	"backup_retention_period": 14,
	"deletion_protection": true,
}

db(overrides) := fixtures.create("aws_db_instance", "d", object.union(good, overrides))

test_allows_a_private_encrypted_backed_up_protected_database if {
	count(database.deny) == 0 with input as fixtures.plan("prod", [db({})])
}

test_denies_a_public_database if {
	messages := database.deny with input as fixtures.plan("prod", [db({"publicly_accessible": true})])
	some msg in messages
	contains(msg, "POL-DB-1")
}

test_denies_an_unencrypted_database if {
	messages := database.deny with input as fixtures.plan("prod", [db({"storage_encrypted": false})])
	some msg in messages
	contains(msg, "POL-DB-2")
}

test_denies_a_password_given_in_configuration if {
	messages := database.deny with input as fixtures.plan("prod", [db({"password": "hunter2"})])
	some msg in messages
	contains(msg, "POL-DB-3")
}

test_denies_a_password_computed_at_apply if {
	rc := {
		"address": "aws_db_instance.d",
		"type": "aws_db_instance",
		"change": {"actions": ["create"], "after": good, "after_unknown": {"password": true}},
	}
	messages := database.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-DB-3")
}

test_denies_a_day_of_backups_in_production if {
	messages := database.deny with input as fixtures.plan("prod", [db({"backup_retention_period": 1})])
	some msg in messages
	contains(msg, "POL-DB-4")
}

test_allows_a_day_of_backups_in_dev if {
	count(database.deny) == 0 with input as fixtures.plan("dev", [db({"backup_retention_period": 1, "deletion_protection": false})])
}

test_denies_no_deletion_protection_in_staging if {
	messages := database.deny with input as fixtures.plan("stg", [db({"deletion_protection": false})])
	some msg in messages
	contains(msg, "POL-DB-5")
}

test_allows_protection_to_be_lifted_for_a_teardown if {
	teardown := object.union(
		fixtures.plan("stg", [db({"deletion_protection": false})]),
		{"variables": {
			"project": {"value": "meridian"},
			"environment": {"value": "stg"},
			"aws_region": {"value": "eu-west-1"},
			"disposable": {"value": true},
		}},
	)
	count(database.deny) == 0 with input as teardown
}
