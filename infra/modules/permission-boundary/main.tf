# The most a workload role in one environment can ever be allowed to do.
#
# A permission boundary grants nothing by itself. A role's effective
# permissions are the overlap of its own policies and its boundary, so a
# role can do something only if both allow it. Attaching this boundary to
# every workload role means that a careless or malicious policy on one role
# still cannot reach another environment's resources, another region, or
# IAM itself.
#
# Resources are matched by the naming standard: everything the platform
# creates in an environment starts with <project>-<environment>- or lives
# under the path /<project>/<environment>/.

locals {
  arn = "arn:aws"
  rp  = var.resource_prefix
  pp  = var.path_prefix
  ra  = "${var.region}:${var.account_id}"
}

data "aws_iam_policy_document" "this" {
  # Exact actions, on purpose. s3:PutObject* would include PutObjectAcl,
  # and s3:DeleteObject* would include DeleteObjectVersion, which lets a
  # workload destroy the old versions that bucket versioning exists to keep.
  statement {
    sid = "ObjectStorageOfThisEnvironment"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:DeleteObject",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:GetObjectTagging",
      "s3:GetObjectVersion",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
      "s3:ListMultipartUploadParts",
      "s3:PutObject",
      "s3:PutObjectTagging",
    ]
    resources = [
      "${local.arn}:s3:::${local.rp}*",
    ]
  }

  statement {
    sid       = "TablesOfThisEnvironment"
    actions   = ["dynamodb:*Item", "dynamodb:Query", "dynamodb:Scan", "dynamodb:DescribeTable", "dynamodb:DescribeStream", "dynamodb:GetRecords", "dynamodb:GetShardIterator", "dynamodb:ListStreams", "dynamodb:ConditionCheckItem"]
    resources = ["${local.arn}:dynamodb:${local.ra}:table/${local.rp}*"]
  }

  statement {
    sid = "MessagingOfThisEnvironment"
    actions = [
      "sqs:SendMessage",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:ChangeMessageVisibility",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sns:Publish",
      "kinesis:PutRecord*",
      "kinesis:GetRecords",
      "kinesis:GetShardIterator",
      "kinesis:DescribeStream*",
      "kinesis:ListShards",
      "kinesis:SubscribeToShard",
      "firehose:PutRecord*",
      "events:PutEvents",
    ]
    resources = [
      "${local.arn}:sqs:${local.ra}:${local.rp}*",
      "${local.arn}:sns:${local.ra}:${local.rp}*",
      "${local.arn}:kinesis:${local.ra}:stream/${local.rp}*",
      "${local.arn}:firehose:${local.ra}:deliverystream/${local.rp}*",
      "${local.arn}:events:${local.ra}:event-bus/${local.rp}*",
    ]
  }

  statement {
    sid = "WorkflowsAndFunctionsOfThisEnvironment"
    actions = [
      "states:StartExecution",
      "states:DescribeExecution",
      "states:StopExecution",
      "states:SendTask*",
      "lambda:InvokeFunction",
    ]
    resources = [
      "${local.arn}:states:${local.ra}:stateMachine:${local.rp}*",
      "${local.arn}:states:${local.ra}:execution:${local.rp}*",
      "${local.arn}:lambda:${local.ra}:function:${local.rp}*",
    ]
  }

  statement {
    sid = "ConfigurationAndSecretsOfThisEnvironment"
    actions = [
      "ssm:GetParameter*",
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [
      "${local.arn}:ssm:${local.ra}:parameter${local.pp}*",
      "${local.arn}:secretsmanager:${local.ra}:secret:${local.pp}*",
    ]
  }

  statement {
    sid = "LogsOfThisEnvironment"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = ["${local.arn}:logs:${local.ra}:log-group:${local.pp}*"]
  }

  statement {
    sid = "ImagesOfThisEnvironment"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = ["${local.arn}:ecr:${local.ra}:repository/${local.rp}*"]
  }

  # Key identifiers are random, so keys cannot be matched by name. Use is
  # limited to keys in this account and region. Which key a role may use is
  # then decided by the role's own policy.
  statement {
    sid = "UseKeysOfThisAccount"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey*",
    ]
    resources = ["${local.arn}:kms:${local.ra}:key/*"]
  }

  statement {
    sid       = "QueryTheDataLake"
    actions   = ["athena:StartQueryExecution", "athena:GetQueryExecution", "athena:GetQueryResults", "athena:StopQueryExecution", "glue:GetDatabase*", "glue:GetTable*", "glue:GetPartition*"]
    resources = ["${local.arn}:athena:${local.ra}:workgroup/${local.rp}*", "${local.arn}:glue:${local.ra}:catalog", "${local.arn}:glue:${local.ra}:database/${replace(local.rp, "-", "_")}*", "${local.arn}:glue:${local.ra}:table/${replace(local.rp, "-", "_")}*"]
  }

  # Actions that AWS does not allow to be limited to a resource.
  statement {
    sid = "ActionsWithoutAResource"
    actions = [
      "cloudwatch:PutMetricData",
      "ecr:GetAuthorizationToken",
      "sts:GetCallerIdentity",
      "xray:PutTelemetryRecords",
      "xray:PutTraceSegments",
    ]
    resources = ["*"]
  }

  # Network interfaces for functions and tasks that run inside the VPC.
  statement {
    sid = "NetworkInterfacesForVpcWorkloads"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DeleteNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  # Explicit denies hold even if a later edit widens the allows above.
  statement {
    sid       = "NeverChangeIdentityOrAccess"
    effect    = "Deny"
    actions   = ["iam:*", "organizations:*", "account:*"]
    resources = ["*"]
  }

  statement {
    sid    = "NeverWeakenKeysVersioningOrAuditing"
    effect = "Deny"
    actions = [
      "s3:DeleteObjectVersion",
      "s3:PutBucketVersioning",
      "s3:PutLifecycleConfiguration",
      "kms:CreateGrant",
      "kms:DisableKey",
      "kms:PutKeyPolicy",
      "kms:ScheduleKeyDeletion",
      "cloudtrail:DeleteTrail",
      "cloudtrail:StopLogging",
      "cloudtrail:UpdateTrail",
      "logs:DeleteLogGroup",
      "logs:DeleteLogStream",
      "logs:PutRetentionPolicy",
    ]
    resources = ["*"]
  }

  statement {
    sid         = "NeverLeaveTheRegion"
    effect      = "Deny"
    not_actions = ["sts:GetCallerIdentity"]
    resources   = ["*"]

    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }
}

resource "aws_iam_policy" "this" {
  name        = var.name
  description = "Permission boundary for workload roles: the most a workload role in this environment can be allowed to do."
  policy      = data.aws_iam_policy_document.this.json

  tags = var.tags
}
