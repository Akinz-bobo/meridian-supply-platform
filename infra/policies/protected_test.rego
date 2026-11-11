package terraform.protected_test

import rego.v1

import data.lib.fixtures
import data.terraform.protected

none := {"protected_deletes": []}

delete(type, name) := fixtures.change(type, name, ["delete"], null)

replace(type, name) := fixtures.change(type, name, ["delete", "create"], {})

test_denies_deleting_a_database_in_production if {
	input_plan := fixtures.plan("prod", [delete("aws_db_instance", "catalog")])
	messages := protected.deny with input as input_plan with data.exceptions as none
	some msg in messages
	contains(msg, "POL-PROTECT-1")
	contains(msg, "would delete aws_db_instance.catalog")
}

test_denies_replacing_a_bucket_in_staging if {
	input_plan := fixtures.plan("stg", [replace("aws_s3_bucket", "lake")])
	messages := protected.deny with input as input_plan with data.exceptions as none
	some msg in messages
	contains(msg, "would replace aws_s3_bucket.lake")
}

test_warns_and_does_not_deny_in_dev if {
	input_plan := fixtures.plan("dev", [delete("aws_dynamodb_table", "movements")])
	count(protected.deny) == 0 with input as input_plan with data.exceptions as none
	count(protected.warn) == 1 with input as input_plan with data.exceptions as none
}

test_allows_deleting_something_that_holds_no_data if {
	input_plan := fixtures.plan("prod", [delete("aws_sqs_queue", "q")])
	count(protected.deny) == 0 with input as input_plan with data.exceptions as none
}

test_allows_creating_and_updating_stateful_resources if {
	input_plan := fixtures.plan("prod", [
		fixtures.create("aws_db_instance", "new", {}),
		fixtures.change("aws_s3_bucket", "lake", ["update"], {}),
	])
	count(protected.deny) == 0 with input as input_plan with data.exceptions as none
}

test_allows_a_delete_listed_as_an_exception if {
	listed := {"protected_deletes": [{
		"address": "aws_db_instance.catalog",
		"environment": "prod",
		"reason": "Replaced by the new instance after migration",
		"issue": 123,
	}]}
	input_plan := fixtures.plan("prod", [delete("aws_db_instance", "catalog")])
	count(protected.deny) == 0 with input as input_plan with data.exceptions as listed
}

test_an_exception_for_another_environment_does_not_apply if {
	listed := {"protected_deletes": [{"address": "aws_db_instance.catalog", "environment": "stg", "reason": "x", "issue": 1}]}
	input_plan := fixtures.plan("prod", [delete("aws_db_instance", "catalog")])
	count(protected.deny) == 1 with input as input_plan with data.exceptions as listed
}

test_warns_about_an_exception_that_matches_nothing if {
	stale := {"protected_deletes": [{"address": "aws_db_instance.old", "environment": "prod", "reason": "x", "issue": 1}]}
	messages := protected.warn with input as fixtures.plan("prod", []) with data.exceptions as stale
	some msg in messages
	contains(msg, "POL-PROTECT-2")
}
