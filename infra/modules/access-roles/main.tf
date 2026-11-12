# The roles through which people and the pipeline enter an environment.
#
# Nobody has a user in an environment account. People sign in to a separate
# identity account and assume a role here, with multi-factor authentication.
# The pipeline has no stored credentials at all: GitHub Actions exchanges a
# short-lived token for the deploy role through OpenID Connect.
#
#   deploy    the pipeline. Manages the platform's resources.
#   operator  on-call engineers. Reads everything, runs a short list of
#             operational actions, changes no infrastructure.
#   audit     security review. Reads configuration, never data.

locals {
  arn         = "arn:aws"
  ra          = "${var.region}:${var.account_id}"
  github_host = "token.actions.githubusercontent.com"

  # The provider's ARN follows from the account and the host. Building it
  # here keeps the trust policy known at plan time, so it can be reviewed
  # and policy checked before anything is created.
  github_arn = "${local.arn}:iam::${var.account_id}:oidc-provider/${local.github_host}"
}

# GitHub's identity provider. One per account.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://${local.github_host}"
  client_id_list = ["sts.amazonaws.com"]

  tags = var.tags
}

# Deploy

data "aws_iam_policy_document" "deploy_assume" {
  statement {
    sid     = "GitHubActionsForThisRepository"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    # The subject names the repository and what the workflow is running
    # for. Without this any repository on GitHub could assume the role.
    condition {
      test     = "StringEquals"
      variable = "${local.github_host}:sub"
      values   = sort(tolist(var.deploy_subjects))
    }
  }
}

data "aws_iam_policy_document" "deploy" {
  # Terraform manages every kind of resource the platform uses, so these
  # are whole services. They are limited to one region, and the statements
  # below take IAM and the access model itself out of reach.
  statement {
    sid       = "ManagePlatformServicesInTheRegion"
    actions   = [for service in sort(tolist(var.deploy_services)) : "${service}:*"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  statement {
    sid     = "ManageRolesAndPoliciesOfThePlatform"
    actions = ["iam:*"]
    resources = [
      "${local.arn}:iam::${var.account_id}:role/${var.resource_prefix}*",
      "${local.arn}:iam::${var.account_id}:policy/${var.resource_prefix}*",
      "${local.arn}:iam::${var.account_id}:instance-profile/${var.resource_prefix}*",
    ]
  }

  statement {
    sid       = "ReadIdentityConfiguration"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }

  # Privilege escalation, closed three ways.
  #
  # 1. A role can be created or given permissions only if it carries the
  #    workload boundary, so the pipeline cannot mint an administrator.
  statement {
    sid    = "NewRolesMustCarryTheBoundary"
    effect = "Deny"
    actions = [
      "iam:AttachRolePolicy",
      "iam:CreateRole",
      "iam:DeleteRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePermissionsBoundary",
      "iam:PutRolePolicy",
    ]
    resources = ["*"]

    condition {
      test     = "StringNotEquals"
      variable = "iam:PermissionsBoundary"
      values   = [var.permissions_boundary_arn]
    }
  }

  # 2. The boundary cannot be removed from a role or rewritten.
  statement {
    sid       = "TheBoundaryCannotBeRemoved"
    effect    = "Deny"
    actions   = ["iam:DeleteRolePermissionsBoundary"]
    resources = ["*"]
  }

  # 3. The pipeline cannot change the boundary, itself or the other access
  #    roles. Those change through an administrator.
  statement {
    sid    = "TheAccessModelIsNotThePipelinesToChange"
    effect = "Deny"
    actions = [
      "iam:Attach*",
      "iam:Create*",
      "iam:Delete*",
      "iam:Detach*",
      "iam:Put*",
      "iam:SetDefaultPolicyVersion",
      "iam:Update*",
    ]
    resources = [
      var.permissions_boundary_arn,
      "${local.arn}:iam::${var.account_id}:role/${var.name}-deploy",
      "${local.arn}:iam::${var.account_id}:role/${var.name}-operator",
      "${local.arn}:iam::${var.account_id}:role/${var.name}-audit",
      "${local.arn}:iam::${var.account_id}:policy/${var.name}-deploy",
      "${local.arn}:iam::${var.account_id}:policy/${var.name}-operator",
      "${local.arn}:iam::${var.account_id}:oidc-provider/*",
    ]
  }

  # Deleting or disabling a key makes everything it encrypted unreadable.
  # A plan that deletes a key is stopped by a policy check, and that only
  # protects against plans. This protects against a direct API call made
  # with the pipeline's credentials. An environment whose data is
  # disposable may switch it off so that it can be torn down.
  dynamic "statement" {
    for_each = var.allow_key_deletion ? [] : [1]

    content {
      sid       = "KeysAreNotThePipelinesToDestroy"
      effect    = "Deny"
      actions   = ["kms:DisableKey", "kms:ScheduleKeyDeletion"]
      resources = ["*"]
    }
  }

  # Terraform state for this environment only, in the shared bucket.
  statement {
    sid       = "ListOwnStatePrefix"
    actions   = ["s3:ListBucket"]
    resources = ["${local.arn}:s3:::${var.state_bucket_name}"]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${var.state_key_prefix}/*"]
    }
  }

  statement {
    sid       = "ReadAndWriteOwnState"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.arn}:s3:::${var.state_bucket_name}/${var.state_key_prefix}/*"]
  }

  statement {
    sid       = "UseTheStateKey"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = ["${local.arn}:kms:${var.region}:${var.state_account_id}:key/*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${var.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "deploy" {
  name        = "${var.name}-deploy"
  description = "What the pipeline may do in this environment."
  policy      = data.aws_iam_policy_document.deploy.json

  tags = var.tags
}

resource "aws_iam_role" "deploy" {
  name                 = "${var.name}-deploy"
  description          = "Assumed by GitHub Actions to plan and apply this environment."
  assume_role_policy   = data.aws_iam_policy_document.deploy_assume.json
  max_session_duration = 3600

  tags = var.tags
  # The trust policy names the provider by a computed ARN, so Terraform
  # does not see the dependency.
  depends_on = [aws_iam_openid_connect_provider.github]
}

resource "aws_iam_role_policy_attachment" "deploy" {
  role       = aws_iam_role.deploy.name
  policy_arn = aws_iam_policy.deploy.arn
}

# People

data "aws_iam_policy_document" "people_assume" {
  statement {
    sid     = "PeopleFromTheIdentityAccountWithMfa"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["${local.arn}:iam::${var.identity_account_id}:root"]
    }

    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }

    # A session older than an hour must authenticate again.
    condition {
      test     = "NumericLessThan"
      variable = "aws:MultiFactorAuthAge"
      values   = ["3600"]
    }
  }
}

data "aws_iam_policy_document" "operator" {
  statement {
    sid = "OperateWorkloadsOfThisEnvironment"
    actions = [
      "ecs:StopTask",
      "ecs:UpdateService",
      "lambda:InvokeFunction",
      "states:StartExecution",
      "states:StopExecution",
      "sqs:StartMessageMoveTask",
      "sqs:CancelMessageMoveTask",
      "rds:CreateDBSnapshot",
      "rds:RebootDBInstance",
    ]
    resources = [
      "${local.arn}:ecs:${local.ra}:service/${var.resource_prefix}*",
      "${local.arn}:ecs:${local.ra}:task/${var.resource_prefix}*",
      "${local.arn}:lambda:${local.ra}:function:${var.resource_prefix}*",
      "${local.arn}:states:${local.ra}:stateMachine:${var.resource_prefix}*",
      "${local.arn}:states:${local.ra}:execution:${var.resource_prefix}*",
      "${local.arn}:sqs:${local.ra}:${var.resource_prefix}*",
      "${local.arn}:rds:${local.ra}:db:${var.resource_prefix}*",
      "${local.arn}:rds:${local.ra}:snapshot:${var.resource_prefix}*",
    ]
  }

  statement {
    sid = "ReadLogsOfThisEnvironment"
    actions = [
      "logs:FilterLogEvents",
      "logs:GetLogEvents",
      "logs:GetQueryResults",
      "logs:StartQuery",
      "logs:StopQuery",
    ]
    resources = ["${local.arn}:logs:${local.ra}:log-group:${var.path_prefix}*"]
  }

  # Granted by alias and not by key ARN. The alias is known at plan time,
  # so this policy can be rendered and checked before the key exists.
  statement {
    sid       = "DecryptLogs"
    actions   = ["kms:Decrypt"]
    resources = ["${local.arn}:kms:${local.ra}:key/*"]

    condition {
      test     = "ForAnyValue:StringEquals"
      variable = "kms:ResourceAliases"
      values   = [var.logs_key_alias]
    }
  }

  statement {
    sid       = "AcknowledgeAlarms"
    actions   = ["cloudwatch:SetAlarmState", "cloudwatch:DisableAlarmActions", "cloudwatch:EnableAlarmActions"]
    resources = ["${local.arn}:cloudwatch:${local.ra}:alarm:${var.resource_prefix}*"]
  }
}

resource "aws_iam_policy" "operator" {
  name        = "${var.name}-operator"
  description = "Operational actions an on-call engineer may take in this environment."
  policy      = data.aws_iam_policy_document.operator.json

  tags = var.tags
}

resource "aws_iam_role" "operator" {
  name                 = "${var.name}-operator"
  description          = "Assumed by on-call engineers to investigate and operate this environment."
  assume_role_policy   = data.aws_iam_policy_document.people_assume.json
  max_session_duration = 3600

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "operator" {
  for_each = {
    operate = aws_iam_policy.operator.arn
    # Lists and describes resources. Unlike ReadOnlyAccess it cannot read
    # objects, items or messages.
    view = "${local.arn}:iam::aws:policy/job-function/ViewOnlyAccess"
  }

  role       = aws_iam_role.operator.name
  policy_arn = each.value
}

resource "aws_iam_role" "audit" {
  name                 = "${var.name}-audit"
  description          = "Assumed by security reviewers to read configuration. Cannot read data or change anything."
  assume_role_policy   = data.aws_iam_policy_document.people_assume.json
  max_session_duration = 3600

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "audit" {
  for_each = {
    security-audit = "${local.arn}:iam::aws:policy/SecurityAudit"
    view           = "${local.arn}:iam::aws:policy/job-function/ViewOnlyAccess"
  }

  role       = aws_iam_role.audit.name
  policy_arn = each.value
}
