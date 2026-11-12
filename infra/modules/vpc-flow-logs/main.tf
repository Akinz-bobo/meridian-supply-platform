# Records accepted and rejected traffic for a VPC in a CloudWatch log group.
#
# The delivery role can write to this one log group and nothing else, and
# only the flow logs service in this account can assume it.

data "aws_iam_policy_document" "assume" {
  statement {
    sid     = "FlowLogsServiceOnly"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }

    # Without this, the flow logs service acting for another account could
    # be tricked into using this role (the confused deputy problem).
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }
  }
}

data "aws_iam_policy_document" "deliver" {
  statement {
    sid = "WriteToTheFlowLogGroup"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = [
      aws_cloudwatch_log_group.this.arn,
      "${aws_cloudwatch_log_group.this.arn}:log-stream:*",
    ]
  }
}

resource "aws_cloudwatch_log_group" "this" {
  name              = var.log_group_name
  retention_in_days = var.retention_in_days
  kms_key_id        = var.kms_key_arn

  tags = var.tags
}

resource "aws_iam_role" "this" {
  name               = "${var.name}-flow-logs-role"
  description        = "Lets VPC flow logs write to ${var.log_group_name}."
  assume_role_policy = data.aws_iam_policy_document.assume.json

  tags = var.tags
}

resource "aws_iam_role_policy" "this" {
  name   = "deliver-flow-logs"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.deliver.json
}

resource "aws_flow_log" "this" {
  vpc_id                   = var.vpc_id
  traffic_type             = var.traffic_type
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.this.arn
  iam_role_arn             = aws_iam_role.this.arn
  max_aggregation_interval = var.max_aggregation_interval

  tags = merge(var.tags, { Name = "${var.name}-flow-logs" })
}
