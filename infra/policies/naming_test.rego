package terraform.naming_test

import rego.v1

import data.lib.fixtures
import data.terraform.naming

test_allows_a_name_with_the_environment_prefix if {
	rc := fixtures.create("aws_sqs_queue", "q", {"name": "meridian-prod-budget-goods-received-dlq"})
	count(naming.deny) == 0 with input as fixtures.plan("prod", [rc])
}

test_allows_a_fifo_queue_suffix if {
	rc := fixtures.create("aws_sqs_queue", "q", {"name": "meridian-prod-inventory-movements.fifo"})
	count(naming.deny) == 0 with input as fixtures.plan("prod", [rc])
}

test_denies_a_name_without_the_prefix if {
	rc := fixtures.create("aws_s3_bucket", "b", {"bucket": "my-test-bucket"})
	messages := naming.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-NAME-1")
}

test_denies_a_name_carrying_another_environments_prefix if {
	rc := fixtures.create("aws_dynamodb_table", "t", {"name": "meridian-dev-inventory-movements"})
	messages := naming.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-NAME-1")
}

test_denies_upper_case_and_underscores if {
	rc := fixtures.create("aws_iam_role", "r", {"name": "meridian-prod-Catalog_TaskRole"})
	messages := naming.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-NAME-2")
}

test_allows_a_parameter_under_the_environment_path if {
	rc := fixtures.create("aws_ssm_parameter", "p", {"name": "/meridian/prod/network/vpc-id"})
	count(naming.deny) == 0 with input as fixtures.plan("prod", [rc])
}

test_denies_a_parameter_outside_the_environment_path if {
	rc := fixtures.create("aws_ssm_parameter", "p", {"name": "/config/vpc-id"})
	messages := naming.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-NAME-3")
}

test_denies_a_key_alias_without_the_prefix if {
	rc := fixtures.create("aws_kms_alias", "k", {"name": "alias/data"})
	messages := naming.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-NAME-4")
}

test_allows_a_key_alias_with_the_prefix if {
	rc := fixtures.create("aws_kms_alias", "k", {"name": "alias/meridian-prod-data"})
	count(naming.deny) == 0 with input as fixtures.plan("prod", [rc])
}

test_ignores_types_that_are_not_named_by_us if {
	rc := fixtures.create("aws_route_table_association", "rta", {"subnet_id": "subnet-123"})
	count(naming.deny) == 0 with input as fixtures.plan("prod", [rc])
}

test_skips_a_name_that_is_not_known_until_apply if {
	rc := object.union(
		fixtures.create("aws_s3_bucket", "b", {}),
		{"change": {"actions": ["create"], "after": {}, "after_unknown": {"bucket": true}}},
	)
	count(naming.deny) == 0 with input as fixtures.plan("prod", [rc])
}

test_allows_a_subnet_with_a_prefixed_name_tag if {
	rc := fixtures.create("aws_subnet", "s", {"tags": {"Name": "meridian-prod-network-data-a"}})
	count(naming.deny) == 0 with input as fixtures.plan("prod", [rc])
}

test_denies_a_subnet_without_a_name_tag if {
	rc := fixtures.create("aws_subnet", "s", {"tags": {"Tier": "data"}})
	messages := naming.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-NAME-5")
}

test_denies_a_vpc_named_for_another_environment if {
	rc := fixtures.create("aws_vpc", "v", {"tags": {"Name": "meridian-dev-network"}})
	messages := naming.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-NAME-5")
}

test_denies_a_network_resource_with_no_tags_at_all if {
	rc := fixtures.create("aws_route_table", "r", {})
	messages := naming.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-NAME-5")
}

test_denies_a_secret_outside_the_environment_path if {
	rc := fixtures.create("aws_secretsmanager_secret", "s", {"name": "catalog-db-password"})
	messages := naming.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-NAME-3")
}

test_allows_a_secret_under_its_service_path if {
	rc := fixtures.create("aws_secretsmanager_secret", "s", {"name": "/meridian/prod/catalog/secrets/partner-api-token"})
	count(naming.deny) == 0 with input as fixtures.plan("prod", [rc])
}

test_allows_a_log_group_named_by_an_aws_service_for_our_resource if {
	rc := fixtures.create("aws_cloudwatch_log_group", "g", {"name": "/aws/rds/instance/meridian-prod-catalog-db/postgresql"})
	count(naming.deny) == 0 with input as fixtures.plan("prod", [rc])
}

test_denies_an_aws_log_group_for_another_environments_resource if {
	rc := fixtures.create("aws_cloudwatch_log_group", "g", {"name": "/aws/rds/instance/meridian-dev-catalog-db/postgresql"})
	messages := naming.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-NAME-3")
}

test_denies_an_aws_log_group_for_an_unnamed_resource if {
	rc := fixtures.create("aws_cloudwatch_log_group", "g", {"name": "/aws/lambda/my-function"})
	messages := naming.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-NAME-3")
}
