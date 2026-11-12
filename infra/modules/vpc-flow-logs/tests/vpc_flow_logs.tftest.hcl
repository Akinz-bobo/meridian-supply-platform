# Plan-only tests against a mocked provider. No AWS account or emulator is
# needed.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  name           = "meridian-prod-network"
  vpc_id         = "vpc-0123456789abcdef0"
  account_id     = "333333333333"
  log_group_name = "/meridian/prod/network/flow-logs"
  tags = {
    Project = "meridian"
  }
}

run "records_all_traffic_by_default" {
  command = plan

  assert {
    condition     = aws_flow_log.this.traffic_type == "ALL"
    error_message = "Rejected traffic alone hides what an intruder succeeded in doing. The default must be ALL."
  }

  assert {
    condition     = aws_flow_log.this.log_destination_type == "cloud-watch-logs"
    error_message = "Flow logs go to CloudWatch Logs."
  }
}

run "keeps_logs_for_ninety_days_by_default" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 90
    error_message = "The default retention is 90 days."
  }
}

run "names_the_role_after_the_network" {
  command = plan

  assert {
    condition     = aws_iam_role.this.name == "meridian-prod-network-flow-logs-role"
    error_message = "The delivery role is named <name>-flow-logs-role."
  }
}

run "only_the_flow_logs_service_in_this_account_can_assume_the_role" {
  command = plan

  assert {
    condition     = one(data.aws_iam_policy_document.assume.statement).principals == toset([{ type = "Service", identifiers = toset(["vpc-flow-logs.amazonaws.com"]) }])
    error_message = "Only vpc-flow-logs.amazonaws.com may assume the role."
  }

  assert {
    condition = one(data.aws_iam_policy_document.assume.statement).condition == toset([{
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = tolist(["333333333333"])
    }])
    error_message = "The trust policy must be limited to this account."
  }
}

run "the_role_cannot_use_a_wildcard_action" {
  command = plan

  assert {
    condition     = alltrue([for action in one(data.aws_iam_policy_document.deliver.statement).actions : !strcontains(action, "*")])
    error_message = "The delivery policy must list exact actions."
  }
}

run "encrypts_with_the_given_key" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:eu-west-1:333333333333:key/11111111-2222-3333-4444-555555555555"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.kms_key_id == "arn:aws:kms:eu-west-1:333333333333:key/11111111-2222-3333-4444-555555555555"
    error_message = "The log group must use the key it was given."
  }
}

run "rejects_retention_shorter_than_thirty_days" {
  command = plan

  variables {
    retention_in_days = 7
  }

  expect_failures = [var.retention_in_days]
}

run "rejects_an_unknown_traffic_type" {
  command = plan

  variables {
    traffic_type = "SOME"
  }

  expect_failures = [var.traffic_type]
}

run "rejects_a_log_group_name_that_is_not_a_path" {
  command = plan

  variables {
    log_group_name = "flow-logs"
  }

  expect_failures = [var.log_group_name]
}

run "rejects_a_malformed_account_id" {
  command = plan

  variables {
    account_id = "1234"
  }

  expect_failures = [var.account_id]
}
