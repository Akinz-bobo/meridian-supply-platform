package terraform.iam_test

import rego.v1

import data.lib.fixtures
import data.terraform.iam

policy(statement) := json.marshal({"Version": "2012-10-17", "Statement": [statement]})

test_allows_specific_actions_on_specific_resources if {
	document := policy({
		"Effect": "Allow",
		"Action": ["sqs:ReceiveMessage", "sqs:DeleteMessage"],
		"Resource": "arn:aws:sqs:eu-west-1:333333333333:meridian-prod-budget-goods-received",
	})
	rc := fixtures.create("aws_iam_policy", "p", {"policy": document})
	count(iam.deny) == 0 with input as fixtures.plan("prod", [rc])
}

test_denies_every_action_on_every_resource if {
	rc := fixtures.create("aws_iam_policy", "admin", {"policy": policy({"Effect": "Allow", "Action": "*", "Resource": "*"})})
	messages := iam.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-IAM-1")
}

test_denies_the_same_when_written_as_lists if {
	document := policy({"Effect": "Allow", "Action": ["s3:GetObject", "*"], "Resource": ["*"]})
	rc := fixtures.create("aws_iam_role_policy", "inline", {"policy": document})
	messages := iam.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-IAM-1")
}

test_denies_a_whole_service_on_every_resource if {
	rc := fixtures.create("aws_iam_policy", "p", {"policy": policy({"Effect": "Allow", "Action": "s3:*", "Resource": "*"})})
	messages := iam.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-IAM-2")
}

test_allows_a_whole_service_on_a_named_resource if {
	document := policy({"Effect": "Allow", "Action": "s3:*", "Resource": "arn:aws:s3:::meridian-prod-datalake/*"})
	rc := fixtures.create("aws_iam_policy", "p", {"policy": document})
	count(iam.deny) == 0 with input as fixtures.plan("prod", [rc])
}

test_allows_a_wildcard_in_a_deny_statement if {
	rc := fixtures.create("aws_iam_policy", "guard", {"policy": policy({"Effect": "Deny", "Action": "*", "Resource": "*"})})
	count(iam.deny) == 0 with input as fixtures.plan("prod", [rc])
}

test_allows_a_role_assumed_by_a_named_service if {
	trust := policy({"Effect": "Allow", "Action": "sts:AssumeRole", "Principal": {"Service": "ecs-tasks.amazonaws.com"}})
	rc := fixtures.create("aws_iam_role", "task", {"assume_role_policy": trust})
	count(iam.deny) == 0 with input as fixtures.plan("prod", [rc])
}

test_denies_a_role_anyone_can_assume if {
	trust := policy({"Effect": "Allow", "Action": "sts:AssumeRole", "Principal": {"AWS": "*"}})
	rc := fixtures.create("aws_iam_role", "open", {"assume_role_policy": trust})
	messages := iam.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-IAM-3")
}

test_allows_a_wildcard_principal_narrowed_by_a_condition if {
	trust := policy({
		"Effect": "Allow",
		"Action": "sts:AssumeRole",
		"Principal": {"AWS": "*"},
		"Condition": {"StringEquals": {"aws:PrincipalOrgID": "o-example"}},
	})
	rc := fixtures.create("aws_iam_role", "org", {"assume_role_policy": trust})
	count(iam.deny) == 0 with input as fixtures.plan("prod", [rc])
}

test_skips_a_policy_that_is_not_known_until_apply if {
	rc := fixtures.create("aws_iam_policy", "later", {})
	count(iam.deny) == 0 with input as fixtures.plan("prod", [rc])
}
