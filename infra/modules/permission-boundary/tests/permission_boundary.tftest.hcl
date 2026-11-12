# Plan-only tests. The provider is real and is given placeholder
# credentials, because the policy document is rendered locally and the
# tests need to read the JSON that would be sent to AWS. Nothing is called:
# no AWS account or emulator is needed.

provider "aws" {
  region                      = "eu-west-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

variables {
  name            = "meridian-prod-workload-boundary"
  resource_prefix = "meridian-prod-"
  path_prefix     = "/meridian/prod/"
  account_id      = "333333333333"
  region          = "eu-west-1"
  tags = {
    Project = "meridian"
  }
}

run "fits_in_a_managed_policy" {
  command = plan

  # AWS limits a managed policy to 6,144 characters, not counting white space.
  assert {
    condition     = length(replace(data.aws_iam_policy_document.this.json, "/\\s/", "")) < 6144
    error_message = "The boundary is too large to be a managed policy. Split it or tighten it."
  }
}

run "never_allows_everything" {
  command = plan

  assert {
    condition = alltrue([
      for statement in jsondecode(data.aws_iam_policy_document.this.json).Statement :
      !(statement.Effect == "Allow" && contains(flatten([statement.Action]), "*"))
    ])
    error_message = "No allow statement may use the action *."
  }

  assert {
    condition = alltrue([
      for statement in jsondecode(data.aws_iam_policy_document.this.json).Statement :
      alltrue([for action in flatten([try(statement.Action, [])]) : !endswith(action, ":*")])
      if statement.Effect == "Allow"
    ])
    error_message = "No allow statement may grant a whole service."
  }
}

run "scopes_named_resources_to_this_environment" {
  command = plan

  # Every allowed resource is either under this environment's prefix or
  # path, a key in this account and region, or the wildcard on a statement
  # that is allowed to have one.
  assert {
    condition = alltrue(flatten([
      for statement in jsondecode(data.aws_iam_policy_document.this.json).Statement : [
        for resource in flatten([statement.Resource]) :
        strcontains(resource, "meridian-prod-") || strcontains(resource, "meridian_prod_") || strcontains(resource, "/meridian/prod/") || endswith(resource, ":333333333333:key/*") || endswith(resource, ":333333333333:catalog")
      ]
      if statement.Effect == "Allow" && !contains(["ActionsWithoutAResource", "NetworkInterfacesForVpcWorkloads"], statement.Sid)
    ]))
    error_message = "An allow statement reaches a resource outside this environment."
  }
}

run "cannot_reach_another_environment_with_a_similar_name" {
  command = plan

  # meridian-prod- must not match meridian-production-..., which is why the
  # prefix ends with a hyphen.
  assert {
    condition     = strcontains(data.aws_iam_policy_document.this.json, "table/meridian-prod-*")
    error_message = "Table resources must be matched with the hyphenated prefix."
  }
}

run "denies_identity_changes_outright" {
  command = plan

  assert {
    condition = length([
      for statement in jsondecode(data.aws_iam_policy_document.this.json).Statement : statement
      if statement.Effect == "Deny" && contains(flatten([try(statement.Action, [])]), "iam:*")
    ]) == 1
    error_message = "The boundary must deny every IAM action."
  }
}

run "denies_requests_to_other_regions" {
  command = plan

  assert {
    condition = one([
      for statement in jsondecode(data.aws_iam_policy_document.this.json).Statement : statement
      if statement.Sid == "NeverLeaveTheRegion"
    ]).Condition.StringNotEquals["aws:RequestedRegion"] == "eu-west-1"
    error_message = "Requests to any region except the environment's must be denied."
  }
}

run "denies_weakening_keys_and_audit_logs" {
  command = plan

  assert {
    condition = length(setsubtract(
      ["kms:ScheduleKeyDeletion", "kms:PutKeyPolicy", "cloudtrail:StopLogging", "logs:DeleteLogGroup"],
      one([
        for statement in jsondecode(data.aws_iam_policy_document.this.json).Statement : statement
        if statement.Sid == "NeverWeakenKeysOrAuditing"
      ]).Action,
    )) == 0
    error_message = "Key deletion, key policy changes, stopping the trail and deleting logs must all be denied."
  }
}

run "rejects_a_prefix_without_the_trailing_hyphen" {
  command = plan

  variables {
    resource_prefix = "meridian-prod"
  }

  expect_failures = [var.resource_prefix]
}

run "rejects_a_path_without_the_trailing_slash" {
  command = plan

  variables {
    path_prefix = "/meridian/prod"
  }

  expect_failures = [var.path_prefix]
}

run "rejects_a_malformed_region" {
  command = plan

  variables {
    region = "ireland"
  }

  expect_failures = [var.region]
}
