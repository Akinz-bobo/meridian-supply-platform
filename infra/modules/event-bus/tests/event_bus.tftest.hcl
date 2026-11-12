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
  name             = "meridian-prod-events"
  account_id       = "333333333333"
  source_prefix    = "meridian"
  publishers       = ["catalog", "erp-gateway"]
  kms_key_arn      = "arn:aws:kms:eu-west-1:333333333333:key/55555555-5555-5555-5555-555555555555"
  logs_kms_key_arn = "arn:aws:kms:eu-west-1:333333333333:key/33333333-3333-3333-3333-333333333333"
  tags = {
    Project = "meridian"
  }
}

run "encrypts_events_with_the_given_key" {
  command = plan

  assert {
    condition     = aws_cloudwatch_event_bus.this.kms_key_identifier == "arn:aws:kms:eu-west-1:333333333333:key/55555555-5555-5555-5555-555555555555"
    error_message = "The bus must use the key that was passed."
  }
}

run "nothing_outside_the_account_can_publish" {
  command = plan

  assert {
    condition     = jsondecode(data.aws_iam_policy_document.bus.json).Statement[0].Effect == "Deny" && jsondecode(data.aws_iam_policy_document.bus.json).Statement[0].Condition.StringNotEquals["aws:PrincipalAccount"] == "333333333333"
    error_message = "The bus policy must deny publishing to any principal outside the account."
  }

  assert {
    condition     = jsondecode(data.aws_iam_policy_document.bus.json).Statement[0].Resource == "arn:aws:events:eu-west-1:333333333333:event-bus/meridian-prod-events"
    error_message = "The bus policy must name this bus."
  }
}

run "a_publisher_can_use_its_own_source_and_no_other" {
  command = plan

  assert {
    condition     = jsondecode(output.publish_policy_json["catalog"]).Statement[0].Condition.StringEquals["events:source"] == "meridian.catalog"
    error_message = "The catalog publisher must be limited to the source meridian.catalog."
  }

  assert {
    condition     = jsondecode(output.publish_policy_json["erp-gateway"]).Statement[0].Condition.StringEquals["events:source"] == "meridian.erp-gateway"
    error_message = "Each publisher is limited to its own source."
  }

  assert {
    condition     = toset(keys(output.publish_policy_json)) == toset(["catalog", "erp-gateway"])
    error_message = "There is one publish policy per publisher and no more."
  }
}

run "a_publisher_gets_no_more_than_putting_events" {
  command = plan

  assert {
    condition = toset(flatten([
      for statement in jsondecode(output.publish_policy_json["catalog"]).Statement : flatten([statement.Action])
    ])) == toset(["events:PutEvents", "kms:Decrypt", "kms:GenerateDataKey"])
    error_message = "A publisher may put events and use the bus's key, and nothing else. It cannot create rules or read the archive."
  }

  assert {
    condition = one([
      for statement in jsondecode(output.publish_policy_json["catalog"]).Statement : statement
      if statement.Sid == "EncryptEventsOnTheBus"
    ]).Condition.StringEquals["kms:ViaService"] == "events.eu-west-1.amazonaws.com"
    error_message = "The key may be used only by way of EventBridge."
  }
}

run "archives_every_platform_event_for_replay" {
  command = plan

  assert {
    condition     = aws_cloudwatch_event_archive.this.retention_days == 90
    error_message = "Events are kept for 90 days by default."
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_event_archive.this.event_pattern).source[0].prefix == "meridian."
    error_message = "The archive must keep every event whose source starts with the platform's prefix."
  }
}

run "logs_every_event_to_an_encrypted_group_with_retention" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.events.name == "/aws/events/meridian-prod-events"
    error_message = "EventBridge delivers only to log groups under /aws/events/."
  }

  assert {
    condition     = aws_cloudwatch_log_group.events.retention_in_days == 30 && aws_cloudwatch_log_group.events.kms_key_id == "arn:aws:kms:eu-west-1:333333333333:key/33333333-3333-3333-3333-333333333333"
    error_message = "The event log needs retention and the logs key."
  }

  assert {
    condition     = jsondecode(data.aws_iam_policy_document.log_delivery.json).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "333333333333"
    error_message = "Only EventBridge acting for this account may write to the event log."
  }
}

run "rejects_keeping_events_for_ever" {
  command = plan

  variables {
    archive_retention_days = 0
  }

  expect_failures = [var.archive_retention_days]
}

run "rejects_a_publisher_name_that_cannot_be_a_source" {
  command = plan

  variables {
    publishers = ["ERP Gateway"]
  }

  expect_failures = [var.publishers]
}

run "rejects_a_bus_without_a_customer_managed_key" {
  command = plan

  variables {
    kms_key_arn = ""
  }

  expect_failures = [var.kms_key_arn]
}

run "rejects_a_name_too_long_for_an_archive" {
  command = plan

  variables {
    name = "meridian-prod-events-with-a-name-that-goes-on-and-on-and-on"
  }

  expect_failures = [var.name]
}
