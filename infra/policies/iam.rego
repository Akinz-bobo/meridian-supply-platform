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
	not wide_policy_approved(rc)
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

# A policy that has to be wide, recorded with the reason and the controls
# that make it acceptable.
wide_policy_approved(rc) if {
	some exception in data.exceptions.wide_iam_policies
	exception.address == rc.address
}

# Roles that are deliberately outside the workload boundary: the roles
# through which the pipeline and people enter the account.
boundary_not_required(rc) if {
	some exception in data.exceptions.roles_without_boundary
	exception.address == rc.address
}

deny contains msg if {
	some rc in plan.changing
	rc.type == "aws_iam_role"
	not plan.unknown(rc, "permissions_boundary")
	object.get(rc.change.after, "permissions_boundary", null) in {"", null}
	not boundary_not_required(rc)
	msg := sprintf(
		"POL-IAM-4: %s has no permission boundary. Set permissions_boundary to the workload boundary",
		[rc.address],
	)
}

# A document that is not known until apply cannot be checked by POL-IAM-1
# or POL-IAM-2. This does not fail the plan. It tells the reviewer that
# nothing has looked at the policy.
warn contains msg if {
	some rc in plan.changing
	attribute := permission_attribute[rc.type]
	plan.unknown(rc, attribute)
	msg := sprintf(
		"POL-IAM-5: the policy document of %s is not known until apply, so it was not checked. Build it from values known at plan time",
		[rc.address],
	)
}
