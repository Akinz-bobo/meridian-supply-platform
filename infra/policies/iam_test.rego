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
	rc := fixtures.create("aws_iam_role", "task", {"assume_role_policy": trust, "permissions_boundary": "arn:aws:iam::333333333333:policy/meridian-prod-workload-boundary"})
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
	rc := fixtures.create("aws_iam_role", "org", {"assume_role_policy": trust, "permissions_boundary": "arn:aws:iam::333333333333:policy/meridian-prod-workload-boundary"})
	count(iam.deny) == 0 with input as fixtures.plan("prod", [rc])
}

test_skips_a_policy_that_is_not_known_until_apply if {
	rc := fixtures.create("aws_iam_policy", "later", {})
	count(iam.deny) == 0 with input as fixtures.plan("prod", [rc])
}

wide := "{\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"s3:*\"],\"Resource\":\"*\"}]}"

test_allows_a_wide_policy_that_is_a_recorded_exception if {
	rc := object.union(
		fixtures.create("aws_iam_policy", "deploy", {"name": "meridian-prod-access-deploy", "policy": wide}),
		{"address": "module.access_roles.aws_iam_policy.deploy"},
	)
	exceptions := {"wide_iam_policies": [{"address": "module.access_roles.aws_iam_policy.deploy"}]}
	count(iam.deny) == 0 with input as fixtures.plan("prod", [rc]) with data.exceptions as exceptions
}

test_denies_a_wide_policy_at_another_address if {
	rc := fixtures.create("aws_iam_policy", "other", {"name": "meridian-prod-other", "policy": wide})
	exceptions := {"wide_iam_policies": [{"address": "module.access_roles.aws_iam_policy.deploy"}]}
	messages := iam.deny with input as fixtures.plan("prod", [rc]) with data.exceptions as exceptions
	some msg in messages
	contains(msg, "POL-IAM-2")
}

test_an_exception_for_a_wide_policy_does_not_excuse_full_administrator if {
	admin := "{\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"*\",\"Resource\":\"*\"}]}"
	rc := object.union(
		fixtures.create("aws_iam_policy", "deploy", {"name": "meridian-prod-access-deploy", "policy": admin}),
		{"address": "module.access_roles.aws_iam_policy.deploy"},
	)
	exceptions := {"wide_iam_policies": [{"address": "module.access_roles.aws_iam_policy.deploy"}]}
	messages := iam.deny with input as fixtures.plan("prod", [rc]) with data.exceptions as exceptions
	some msg in messages
	contains(msg, "POL-IAM-1")
}

service_trust := "{\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"sts:AssumeRole\",\"Principal\":{\"Service\":\"lambda.amazonaws.com\"}}]}"

test_allows_a_role_with_a_boundary if {
	rc := fixtures.create("aws_iam_role", "r", {
		"name": "meridian-prod-x-role",
		"assume_role_policy": service_trust,
		"permissions_boundary": "arn:aws:iam::333333333333:policy/meridian-prod-workload-boundary",
	})
	count(iam.deny) == 0 with input as fixtures.plan("prod", [rc])
}

test_denies_a_role_without_a_boundary if {
	rc := fixtures.create("aws_iam_role", "r", {"name": "meridian-prod-x-role", "assume_role_policy": service_trust})
	messages := iam.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-IAM-4")
}

test_allows_an_access_role_recorded_as_outside_the_boundary if {
	rc := object.union(
		fixtures.create("aws_iam_role", "audit", {"name": "meridian-prod-access-audit", "assume_role_policy": service_trust}),
		{"address": "module.access_roles.aws_iam_role.audit"},
	)
	exceptions := {"roles_without_boundary": [{"address": "module.access_roles.aws_iam_role.audit"}]}
	count(iam.deny) == 0 with input as fixtures.plan("prod", [rc]) with data.exceptions as exceptions
}

test_warns_when_a_policy_document_is_not_known_at_plan if {
	rc := {
		"address": "aws_iam_role_policy.p",
		"type": "aws_iam_role_policy",
		"change": {"actions": ["create"], "after": {"name": "p"}, "after_unknown": {"policy": true}},
	}
	messages := iam.warn with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-IAM-5")
}

test_does_not_warn_when_the_document_is_known if {
	rc := fixtures.create("aws_iam_role_policy", "p", {"name": "p", "policy": "{\"Statement\":[]}"})
	count(iam.warn) == 0 with input as fixtures.plan("prod", [rc])
}
