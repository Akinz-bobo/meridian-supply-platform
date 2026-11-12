package terraform.tags_test

import rego.v1

import data.lib.fixtures
import data.terraform.tags

test_allows_a_resource_with_every_required_tag if {
	input_plan := fixtures.plan("prod", [fixtures.create("aws_sqs_queue", "q", {"tags_all": fixtures.good_tags})])
	count(tags.deny) == 0 with input as input_plan
}

test_denies_a_resource_missing_required_tags if {
	incomplete := {"Project": "meridian", "Environment": "prod"}
	input_plan := fixtures.plan("prod", [fixtures.create("aws_sqs_queue", "q", {"tags_all": incomplete})])
	messages := tags.deny with input as input_plan
	some msg in messages
	contains(msg, "POL-TAG-1")
	contains(msg, "Component, ManagedBy")
}

test_denies_a_resource_with_no_tags_at_all if {
	input_plan := fixtures.plan("prod", [fixtures.create("aws_sqs_queue", "q", {"tags_all": {}})])
	count(tags.deny) == 1 with input as input_plan
}

test_ignores_resource_types_that_cannot_be_tagged if {
	input_plan := fixtures.plan("prod", [fixtures.create("aws_s3_bucket_versioning", "v", {"bucket": "b"})])
	count(tags.deny) == 0 with input as input_plan
}

test_denies_managed_by_other_than_terraform if {
	by_hand := object.union(fixtures.good_tags, {"ManagedBy": "console"})
	input_plan := fixtures.plan("prod", [fixtures.create("aws_sqs_queue", "q", {"tags_all": by_hand})])
	messages := tags.deny with input as input_plan
	some msg in messages
	contains(msg, "POL-TAG-2")
}

test_denies_an_environment_tag_that_does_not_match_the_target if {
	input_plan := fixtures.plan("dev", [fixtures.create("aws_sqs_queue", "q", {"tags_all": fixtures.good_tags})])
	messages := tags.deny with input as input_plan
	some msg in messages
	contains(msg, "POL-TAG-3")
}

test_ignores_resources_that_are_only_being_deleted if {
	gone := fixtures.change("aws_sqs_queue", "q", ["delete"], {})
	count(tags.deny) == 0 with input as fixtures.plan("prod", [gone])
}

test_warns_and_does_not_deny_when_tags_are_unknown_until_apply if {
	rc := object.union(
		fixtures.create("aws_sqs_queue", "q", {"tags_all": {}}),
		{"change": {"actions": ["create"], "after": {"tags_all": {}}, "after_unknown": {"tags_all": true}}},
	)
	input_plan := fixtures.plan("prod", [rc])
	count(tags.deny) == 0 with input as input_plan
	count(tags.warn) == 1 with input as input_plan
}

classified(level) := object.union(fixtures.good_tags, {"DataClassification": level})

test_allows_a_data_store_with_a_classification if {
	rc := fixtures.create("aws_dynamodb_table", "t", {"tags_all": classified("confidential")})
	count(tags.deny) == 0 with input as fixtures.plan("prod", [rc])
}

test_denies_a_data_store_without_a_classification if {
	rc := fixtures.create("aws_s3_bucket", "b", {"tags_all": fixtures.good_tags})
	messages := tags.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-TAG-4")
}

test_denies_a_classification_that_is_not_in_the_scheme if {
	rc := fixtures.create("aws_db_instance", "d", {"tags_all": classified("secret")})
	messages := tags.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-TAG-4")
}

test_does_not_ask_other_resources_for_a_classification if {
	rc := fixtures.create("aws_sqs_queue", "q", {"tags_all": fixtures.good_tags})
	count(tags.deny) == 0 with input as fixtures.plan("prod", [rc])
}
