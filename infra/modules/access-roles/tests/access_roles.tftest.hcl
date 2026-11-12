# Plan-only tests. The provider is real with placeholder credentials so the
# rendered policies can be read. Nothing is called: no AWS account or
# emulator is needed.

provider "aws" {
  region                      = "eu-west-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

variables {
  name                     = "meridian-prod-access"
  account_id               = "333333333333"
  region                   = "eu-west-1"
  identity_account_id      = "444444444444"
  deploy_subjects          = ["repo:Akinz-bobo/meridian-supply-platform:environment:production"]
  resource_prefix          = "meridian-prod-"
  path_prefix              = "/meridian/prod/"
  permissions_boundary_arn = "arn:aws:iam::333333333333:policy/meridian-prod-workload-boundary"
  logs_key_alias           = "alias/meridian-prod-logs"
  state_bucket_name        = "meridian-shared-tfstate-444444444444-eu-west-1"
  state_key_prefix         = "production"
  state_account_id         = "444444444444"
  tags = {
    Project = "meridian"
  }
}

run "the_pipeline_authenticates_with_a_token_and_no_stored_secret" {
  command = plan

  assert {
    condition     = jsondecode(data.aws_iam_policy_document.deploy_assume.json).Statement[0].Action == "sts:AssumeRoleWithWebIdentity"
    error_message = "The deploy role is assumed with a web identity token."
  }

  assert {
    condition     = jsondecode(data.aws_iam_policy_document.deploy_assume.json).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:Akinz-bobo/meridian-supply-platform:environment:production"
    error_message = "The trust policy must name the repository and environment."
  }

  assert {
    condition     = jsondecode(data.aws_iam_policy_document.deploy_assume.json).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com"
    error_message = "The token must have been issued for AWS."
  }
}

run "the_pipeline_cannot_create_a_role_without_the_boundary" {
  command = plan

  assert {
    condition = one([
      for statement in jsondecode(data.aws_iam_policy_document.deploy.json).Statement : statement
      if statement.Sid == "NewRolesMustCarryTheBoundary"
    ]).Condition.StringNotEquals["iam:PermissionsBoundary"] == "arn:aws:iam::333333333333:policy/meridian-prod-workload-boundary"
    error_message = "Creating a role without the boundary must be denied."
  }
}

run "a_service_role_may_carry_an_approved_aws_boundary" {
  command = plan

  variables {
    service_boundary_arns = ["arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"]
  }

  assert {
    condition = toset(one([
      for statement in jsondecode(data.aws_iam_policy_document.deploy.json).Statement : statement
      if statement.Sid == "NewRolesMustCarryTheBoundary"
      ]).Condition.StringNotEquals["iam:PermissionsBoundary"]) == toset([
      "arn:aws:iam::333333333333:policy/meridian-prod-workload-boundary",
      "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup",
    ])
    error_message = "The approved boundaries are the workload boundary and the listed service boundaries, and nothing else."
  }
}

run "rejects_a_customer_managed_policy_as_a_service_boundary" {
  command = plan

  variables {
    service_boundary_arns = ["arn:aws:iam::333333333333:policy/anything"]
  }

  expect_failures = [var.service_boundary_arns]
}

run "rejects_administrator_access_as_a_service_boundary" {
  command = plan

  variables {
    service_boundary_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  }

  expect_failures = [var.service_boundary_arns]
}

run "the_pipeline_cannot_change_its_own_permissions" {
  command = plan

  assert {
    condition = length(setsubtract(
      [
        "arn:aws:iam::333333333333:role/meridian-prod-access-deploy",
        "arn:aws:iam::333333333333:policy/meridian-prod-access-deploy",
        "arn:aws:iam::333333333333:policy/meridian-prod-workload-boundary",
      ],
      one([
        for statement in jsondecode(data.aws_iam_policy_document.deploy.json).Statement : statement
        if statement.Sid == "TheAccessModelIsNotThePipelinesToChange"
      ]).Resource,
    )) == 0
    error_message = "The deploy role, its policy and the boundary must all be protected from the pipeline."
  }
}

run "the_pipeline_cannot_destroy_a_key_by_default" {
  command = plan

  assert {
    condition = toset(one([
      for statement in jsondecode(data.aws_iam_policy_document.deploy.json).Statement : statement
      if statement.Sid == "KeysAreNotThePipelinesToDestroy"
    ]).Action) == toset(["kms:DisableKey", "kms:ScheduleKeyDeletion"])
    error_message = "Disabling a key and scheduling its deletion must be denied to the pipeline."
  }
}

run "a_disposable_environment_can_be_torn_down" {
  command = plan

  variables {
    allow_key_deletion = true
  }

  assert {
    condition = length([
      for statement in jsondecode(data.aws_iam_policy_document.deploy.json).Statement : statement
      if statement.Sid == "KeysAreNotThePipelinesToDestroy"
    ]) == 0
    error_message = "With allow_key_deletion the deny statement must be absent."
  }
}

run "the_pipeline_manages_iam_only_under_the_platform_prefix" {
  command = plan

  assert {
    condition = alltrue([
      for resource in one([
        for statement in jsondecode(data.aws_iam_policy_document.deploy.json).Statement : statement
        if statement.Sid == "ManageRolesAndPoliciesOfThePlatform"
      ]).Resource : strcontains(resource, "/meridian-prod-")
    ])
    error_message = "IAM management must be limited to roles and policies named for this environment."
  }
}

run "the_pipeline_is_confined_to_one_region" {
  command = plan

  assert {
    condition = one([
      for statement in jsondecode(data.aws_iam_policy_document.deploy.json).Statement : statement
      if statement.Sid == "ManagePlatformServicesInTheRegion"
    ]).Condition.StringEquals["aws:RequestedRegion"] == "eu-west-1"
    error_message = "Service management must be limited to the environment's region."
  }
}

run "the_pipeline_reaches_only_its_own_state" {
  command = plan

  assert {
    condition = one([
      for statement in jsondecode(data.aws_iam_policy_document.deploy.json).Statement : statement
      if statement.Sid == "ReadAndWriteOwnState"
    ]).Resource == "arn:aws:s3:::meridian-shared-tfstate-444444444444-eu-west-1/production/*"
    error_message = "State access must be limited to this environment's prefix."
  }

  assert {
    condition = one([
      for statement in jsondecode(data.aws_iam_policy_document.deploy.json).Statement : statement
      if statement.Sid == "ListOwnStatePrefix"
    ]).Condition.StringLike["s3:prefix"] == "production/*"
    error_message = "Listing must be limited to this environment's prefix."
  }
}

run "the_deploy_policy_fits_in_a_managed_policy" {
  command = plan

  assert {
    condition     = length(replace(data.aws_iam_policy_document.deploy.json, "/\\s/", "")) < 6144
    error_message = "The deploy policy is too large to be a managed policy."
  }
}

run "people_need_recent_multi_factor_authentication" {
  command = plan

  assert {
    condition     = jsondecode(data.aws_iam_policy_document.people_assume.json).Statement[0].Condition.Bool["aws:MultiFactorAuthPresent"] == "true"
    error_message = "The operator and audit roles require multi-factor authentication."
  }

  assert {
    condition     = jsondecode(data.aws_iam_policy_document.people_assume.json).Statement[0].Principal.AWS == "arn:aws:iam::444444444444:root"
    error_message = "Only the identity account may assume the people roles."
  }
}

run "operators_change_no_infrastructure" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for statement in jsondecode(data.aws_iam_policy_document.operator.json).Statement : [
        for action in flatten([statement.Action]) :
        !strcontains(action, "*") && !startswith(action, "iam:") && !can(regex(":(Create|Delete|Put)(Function|Table|Bucket|Queue|Role|Cluster)", action))
      ]
    ]))
    error_message = "The operator policy lists exact operational actions and cannot create or delete infrastructure."
  }

  assert {
    condition = alltrue(flatten([
      for statement in jsondecode(data.aws_iam_policy_document.operator.json).Statement : [
        for resource in flatten([statement.Resource]) : resource != "*"
      ]
    ]))
    error_message = "No operator statement may apply to every resource."
  }
}

run "operators_decrypt_logs_and_nothing_else" {
  command = plan

  assert {
    condition = one([
      for statement in jsondecode(data.aws_iam_policy_document.operator.json).Statement : statement
      if statement.Sid == "DecryptLogs"
    ]).Condition["ForAnyValue:StringEquals"]["kms:ResourceAliases"] == "alias/meridian-prod-logs"
    error_message = "Operators may decrypt only with the key behind the logs alias."
  }
}

run "auditors_get_configuration_and_no_data" {
  command = plan

  assert {
    condition     = toset([for attachment in aws_iam_role_policy_attachment.audit : attachment.policy_arn]) == toset(["arn:aws:iam::aws:policy/SecurityAudit", "arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"])
    error_message = "The audit role has SecurityAudit and ViewOnlyAccess, and not ReadOnlyAccess, which can read data."
  }
}

run "rejects_a_wildcard_subject" {
  command = plan

  variables {
    deploy_subjects = ["repo:Akinz-bobo/meridian-supply-platform:*"]
  }

  expect_failures = [var.deploy_subjects]
}

run "rejects_a_pull_request_subject" {
  command = plan

  variables {
    deploy_subjects = ["repo:Akinz-bobo/meridian-supply-platform:pull_request"]
  }

  expect_failures = [var.deploy_subjects]
}

run "rejects_iam_among_the_managed_services" {
  command = plan

  variables {
    deploy_services = ["s3", "iam"]
  }

  expect_failures = [var.deploy_services]
}
