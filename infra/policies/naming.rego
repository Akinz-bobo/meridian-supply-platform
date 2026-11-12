# POL-NAME: resource names follow <project>-<environment>-<component>.
#
# The standard is in docs/architecture/environments.md. A name that says
# where a resource lives prevents acting on the wrong environment, and makes
# IAM policies by name prefix possible.
package terraform.naming

import rego.v1

import data.lib.plan

# Which attribute holds the name, for the resource types we name ourselves.
name_attribute := {
	"aws_cloudwatch_event_archive": "name",
	"aws_cloudwatch_event_bus": "name",
	"aws_cloudwatch_event_rule": "name",
	"aws_db_instance": "identifier",
	"aws_db_subnet_group": "name",
	"aws_dynamodb_table": "name",
	"aws_ecr_repository": "name",
	"aws_ecs_cluster": "name",
	"aws_ecs_service": "name",
	"aws_eks_cluster": "name",
	"aws_elasticache_replication_group": "replication_group_id",
	"aws_iam_policy": "name",
	"aws_iam_role": "name",
	"aws_kinesis_stream": "name",
	"aws_lambda_function": "function_name",
	"aws_lb": "name",
	"aws_s3_bucket": "bucket",
	"aws_security_group": "name",
	"aws_sfn_state_machine": "name",
	"aws_sns_topic": "name",
	"aws_sqs_queue": "name",
}

# Types named as a path: /<project>/<environment>/...
path_attribute := {
	"aws_cloudwatch_log_group": "name",
	"aws_secretsmanager_secret": "name",
	"aws_ssm_parameter": "name",
}

prefix := sprintf("%s-%s-", [plan.project, plan.environment])

path_prefix := sprintf("/%s/%s/", [plan.project, plan.environment])

deny contains msg if {
	some rc in plan.changing
	attribute := name_attribute[rc.type]
	not plan.unknown(rc, attribute)
	name := rc.change.after[attribute]
	is_string(name)
	not startswith(name, prefix)
	msg := sprintf("POL-NAME-1: %s is named %q. Names must start with %q", [rc.address, name, prefix])
}

deny contains msg if {
	some rc in plan.changing
	attribute := name_attribute[rc.type]
	name := rc.change.after[attribute]
	is_string(name)
	startswith(name, prefix)
	not regex.match(`^[a-z0-9]+(-[a-z0-9]+)*(\.fifo)?$`, name)
	msg := sprintf(
		"POL-NAME-2: %s is named %q. Names are lower case letters, digits and single hyphens",
		[rc.address, name],
	)
}

deny contains msg if {
	some rc in plan.changing
	attribute := path_attribute[rc.type]
	not plan.unknown(rc, attribute)
	name := rc.change.after[attribute]
	is_string(name)
	not startswith(name, path_prefix)
	not named_by_aws(name)
	msg := sprintf("POL-NAME-3: %s is named %q. Paths must start with %q", [rc.address, name, path_prefix])
}

deny contains msg if {
	some rc in plan.changing
	rc.type == "aws_kms_alias"
	name := rc.change.after.name
	is_string(name)
	not startswith(name, concat("", ["alias/", prefix]))
	msg := sprintf("POL-NAME-4: %s is named %q. Key aliases must start with \"alias/%s\"", [rc.address, name, prefix])
}

# Network resources have no name attribute. Their name is the Name tag, and
# it is what an engineer sees in the console when choosing a subnet.
name_tag_types := {
	"aws_eip",
	"aws_internet_gateway",
	"aws_nat_gateway",
	"aws_network_acl",
	"aws_route_table",
	"aws_subnet",
	"aws_vpc",
	"aws_vpc_endpoint",
}

deny contains msg if {
	some rc in plan.changing
	rc.type in name_tag_types
	name := object.get(rc.change.after, ["tags", "Name"], "")
	not startswith(name, prefix)
	msg := sprintf(
		"POL-NAME-5: %s has the Name tag %q. Network resources need a Name tag starting with %q",
		[rc.address, name, prefix],
	)
}

# Some services write to a log group whose name they decide, such as
# /aws/rds/instance/<identifier>/postgresql. The path cannot follow the
# standard, so the resource name inside it must.
named_by_aws(name) if {
	startswith(name, "/aws/")
	contains(name, concat("", ["/", prefix]))
}
