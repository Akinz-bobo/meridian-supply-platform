# The IAM role a workload runs as, on any of the platform's compute types.
#
# The role always carries the environment's permission boundary, so its
# policies can never grant more than the boundary allows. The trust policy
# is derived from the compute type and cannot name an arbitrary principal.

locals {
  # Who may assume the role, per compute type.
  trust = {
    ecs-task = {
      services = ["ecs-tasks.amazonaws.com"]
      actions  = ["sts:AssumeRole"]
      # ECS supports limiting the service to tasks of this account.
      source_account = true
    }
    lambda = {
      services       = ["lambda.amazonaws.com"]
      actions        = ["sts:AssumeRole"]
      source_account = false
    }
    eks-pod = {
      # EKS Pod Identity: the cluster's agent assumes the role for a pod
      # and tags the session with the cluster, namespace and service account.
      services       = ["pods.eks.amazonaws.com"]
      actions        = ["sts:AssumeRole", "sts:TagSession"]
      source_account = true
    }
    ec2 = {
      services       = ["ec2.amazonaws.com"]
      actions        = ["sts:AssumeRole"]
      source_account = false
    }
    step-functions = {
      services       = ["states.amazonaws.com"]
      actions        = ["sts:AssumeRole"]
      source_account = true
    }
    scheduler = {
      services       = ["scheduler.amazonaws.com"]
      actions        = ["sts:AssumeRole"]
      source_account = true
    }
    firehose = {
      services       = ["firehose.amazonaws.com"]
      actions        = ["sts:AssumeRole"]
      source_account = true
    }
  }

  selected = local.trust[var.workload]
}

data "aws_iam_policy_document" "assume" {
  statement {
    sid     = "WorkloadAssumesItsRole"
    actions = local.selected.actions

    principals {
      type        = "Service"
      identifiers = local.selected.services
    }

    dynamic "condition" {
      for_each = local.selected.source_account ? [1] : []

      content {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [var.account_id]
      }
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = var.name
  description          = var.description
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  permissions_boundary = var.permissions_boundary_arn
  max_session_duration = 3600

  tags = var.tags
}

resource "aws_iam_role_policy" "this" {
  for_each = var.policies

  name   = each.key
  role   = aws_iam_role.this.id
  policy = each.value
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = var.managed_policy_arns

  role       = aws_iam_role.this.name
  policy_arn = each.value
}

# An EC2 instance receives its role through an instance profile.
resource "aws_iam_instance_profile" "this" {
  count = var.workload == "ec2" ? 1 : 0

  name = var.name
  role = aws_iam_role.this.name

  tags = var.tags
}
