# POL-IAM: no policy grants everything, and no role can be assumed by anyone.
#
# Least privilege is the security baseline of the platform. These rules
# catch the two shapes that defeat it outright. Finer checks are left to
# review and to IAM Access Analyzer.
package terraform.iam

import rego.v1

import data.lib.plan

# Where each resource type keeps a permissions policy document.
permission_attribute := {
	"aws_iam_group_policy": "policy",
	"aws_iam_policy": "policy",
	"aws_iam_role_policy": "policy",
	"aws_iam_user_policy": "policy",
}

wildcard(value) if "*" in plan.as_list(value)

deny contains msg if {
	some rc in plan.changing
	attribute := permission_attribute[rc.type]
	document := plan.policy_document(rc, attribute)
	some statement in plan.statements(document)
	statement.Effect == "Allow"
	wildcard(statement.Action)
	wildcard(statement.Resource)
	msg := sprintf(
		"POL-IAM-1: %s allows every action on every resource. Grant the specific actions and resources needed",
		[rc.address],
	)
}

deny contains msg if {
	some rc in plan.changing
	attribute := permission_attribute[rc.type]
	document := plan.policy_document(rc, attribute)
	some statement in plan.statements(document)
	statement.Effect == "Allow"
	some action in plan.as_list(statement.Action)
	endswith(action, ":*")
	wildcard(statement.Resource)
	msg := sprintf(
		"POL-IAM-2: %s allows %q on every resource. Name the actions, or restrict the resources",
		[rc.address, action],
	)
}

deny contains msg if {
	some rc in plan.changing
	rc.type == "aws_iam_role"
	document := plan.policy_document(rc, "assume_role_policy")
	some statement in plan.statements(document)
	statement.Effect == "Allow"
	anyone(statement.Principal)
	not statement.Condition
	msg := sprintf(
		"POL-IAM-3: %s can be assumed by any principal. Name the principals, or add a condition",
		[rc.address],
	)
}

anyone(principal) if principal == "*"

anyone(principal) if wildcard(principal.AWS)
