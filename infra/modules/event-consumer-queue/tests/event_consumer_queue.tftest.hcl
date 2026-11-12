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
  name          = "meridian-prod-budget-goods-received"
  account_id    = "333333333333"
  bus_name      = "meridian-prod-events"
  source_prefix = "meridian"
  event_types   = ["GoodsReceived"]
  kms_key_arn   = "arn:aws:kms:eu-west-1:333333333333:key/55555555-5555-5555-5555-555555555555"
  tags = {
    Project = "meridian"
  }
}

run "names_the_dead_letter_queue_after_the_queue" {
  command = plan

  assert {
    condition     = aws_sqs_queue.this.name == "meridian-prod-budget-goods-received" && aws_sqs_queue.dead_letter.name == "meridian-prod-budget-goods-received-dlq"
    error_message = "The dead-letter queue is the queue's name with -dlq."
  }
}

run "encrypts_both_queues_with_the_given_key" {
  command = plan

  assert {
    condition     = aws_sqs_queue.this.kms_master_key_id == "arn:aws:kms:eu-west-1:333333333333:key/55555555-5555-5555-5555-555555555555" && aws_sqs_queue.dead_letter.kms_master_key_id == aws_sqs_queue.this.kms_master_key_id
    error_message = "Both queues must use the key that was passed."
  }
}

run "moves_a_message_aside_after_five_failed_receives" {
  command = plan

  assert {
    condition     = jsondecode(aws_sqs_queue.this.redrive_policy).maxReceiveCount == 5
    error_message = "A message is moved to the dead-letter queue after five receives by default."
  }
}

run "keeps_failed_messages_for_two_weeks" {
  command = plan

  assert {
    condition     = aws_sqs_queue.dead_letter.message_retention_seconds == 14 * 86400
    error_message = "Failed messages are kept for 14 days by default."
  }

  assert {
    condition     = aws_sqs_queue.this.message_retention_seconds == 4 * 86400
    error_message = "Unprocessed messages are kept for 4 days by default."
  }
}

run "waits_for_messages_instead_of_polling_empty" {
  command = plan

  assert {
    condition     = aws_sqs_queue.this.receive_wait_time_seconds == 20
    error_message = "Long polling must be on."
  }
}

run "only_this_modules_rule_can_deliver_to_the_queue" {
  command = plan

  assert {
    condition = one([
      for statement in jsondecode(data.aws_iam_policy_document.queue.json).Statement : statement
      if statement.Sid == "TheRuleDeliversEvents"
    ]).Condition.ArnEquals["aws:SourceArn"] == "arn:aws:events:eu-west-1:333333333333:rule/meridian-prod-events/meridian-prod-budget-goods-received"
    error_message = "Delivery must be limited to the rule this module creates on the given bus."
  }

  assert {
    condition = one([
      for statement in jsondecode(data.aws_iam_policy_document.queue.json).Statement : statement
      if statement.Sid == "TheRuleDeliversEvents"
    ]).Principal.Service == "events.amazonaws.com"
    error_message = "Only EventBridge may send to the queue."
  }
}

run "both_queues_refuse_requests_without_tls" {
  command = plan

  assert {
    condition = alltrue([
      for document in [data.aws_iam_policy_document.queue.json, data.aws_iam_policy_document.dead_letter.json] :
      anytrue([
        for statement in jsondecode(document).Statement :
        statement.Effect == "Deny" && try(statement.Condition.Bool["aws:SecureTransport"], "") == "false"
      ])
    ])
    error_message = "Both queue policies must deny requests that do not use TLS."
  }
}

run "matches_the_event_type_from_any_service_of_the_platform" {
  command = plan

  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.this.event_pattern)["detail-type"] == ["GoodsReceived"]
    error_message = "The rule must match the given event types."
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.this.event_pattern).source[0].prefix == "meridian."
    error_message = "The rule must match only events whose source is a service of the platform."
  }
}

run "delivers_the_envelope_without_the_bus_wrapper" {
  command = plan

  assert {
    condition     = aws_cloudwatch_event_target.this.input_path == "$.detail"
    error_message = "The consumer must receive the event's detail, which is the envelope."
  }
}

run "alarms_on_a_single_failed_message" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.dead_letter.threshold == 0 && aws_cloudwatch_metric_alarm.dead_letter.comparison_operator == "GreaterThanThreshold"
    error_message = "One message in the dead-letter queue must raise the alarm."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.dead_letter.dimensions["QueueName"] == "meridian-prod-budget-goods-received-dlq"
    error_message = "The alarm must watch the dead-letter queue, not the queue."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.dead_letter.treat_missing_data == "notBreaching"
    error_message = "An empty queue reports no data, which must count as healthy."
  }
}

run "sends_the_alarm_where_it_is_told" {
  command = plan

  variables {
    alarm_actions = ["arn:aws:sns:eu-west-1:333333333333:meridian-prod-alarms"]
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.dead_letter.alarm_actions == toset(["arn:aws:sns:eu-west-1:333333333333:meridian-prod-alarms"]) && aws_cloudwatch_metric_alarm.dead_letter.ok_actions == aws_cloudwatch_metric_alarm.dead_letter.alarm_actions
    error_message = "The alarm must notify the given topic when it fires and when it clears."
  }
}

run "the_consumer_can_receive_and_acknowledge_and_nothing_else" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for statement in jsondecode(output.consume_policy_json).Statement : [
        for action in flatten([statement.Action]) :
        !contains(["sqs:SendMessage", "sqs:PurgeQueue", "sqs:DeleteQueue", "sqs:SetQueueAttributes"], action) && !strcontains(action, "*")
      ]
    ]))
    error_message = "The consume policy must not allow sending, purging or changing the queue."
  }

  assert {
    condition = alltrue(flatten([
      for statement in jsondecode(output.consume_policy_json).Statement : [
        for resource in flatten([statement.Resource]) :
        resource == "arn:aws:sqs:eu-west-1:333333333333:meridian-prod-budget-goods-received" || resource == "arn:aws:kms:eu-west-1:333333333333:key/55555555-5555-5555-5555-555555555555"
      ]
    ]))
    error_message = "The consume policy names this queue and its key, and not the dead-letter queue."
  }
}

run "takes_several_event_types_into_one_queue" {
  command = plan

  variables {
    event_types = ["ProductWithdrawn", "ProductPublished"]
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.this.event_pattern)["detail-type"] == ["ProductPublished", "ProductWithdrawn"]
    error_message = "All given types are matched, in a stable order."
  }
}

run "rejects_a_queue_that_matches_nothing" {
  command = plan

  variables {
    event_types = []
  }

  expect_failures = [var.event_types]
}

run "rejects_an_event_type_that_is_not_in_the_contracts_form" {
  command = plan

  variables {
    event_types = ["goods_received"]
  }

  expect_failures = [var.event_types]
}

run "rejects_giving_a_failure_no_second_chance" {
  command = plan

  variables {
    max_receive_count = 1
  }

  expect_failures = [var.max_receive_count]
}

run "rejects_a_queue_without_a_customer_managed_key" {
  command = plan

  variables {
    kms_key_arn = ""
  }

  expect_failures = [var.kms_key_arn]
}

run "rejects_dropping_failed_messages_within_days" {
  command = plan

  variables {
    dead_letter_retention_days = 2
  }

  expect_failures = [var.dead_letter_retention_days]
}

run "an_event_the_bus_cannot_deliver_is_parked_and_not_dropped" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_event_target.this.dead_letter_config) == 1
    error_message = "The target must have a dead-letter queue, or an undeliverable event is discarded after a day."
  }

  assert {
    condition     = one(aws_cloudwatch_event_target.this.retry_policy).maximum_event_age_in_seconds == 3600
    error_message = "The bus retries delivery for an hour by default."
  }

  assert {
    condition = one([
      for statement in jsondecode(data.aws_iam_policy_document.dead_letter.json).Statement : statement
      if statement.Sid == "TheRuleParksUndeliveredEvents"
    ]).Condition.ArnEquals["aws:SourceArn"] == "arn:aws:events:eu-west-1:333333333333:rule/meridian-prod-events/meridian-prod-budget-goods-received"
    error_message = "Only this module's rule may send to the dead-letter queue."
  }
}

run "alarms_when_the_consumer_falls_behind" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.backlog.metric_name == "ApproximateAgeOfOldestMessage" && aws_cloudwatch_metric_alarm.backlog.threshold == 900
    error_message = "The backlog alarm fires when the oldest message is older than 15 minutes by default."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.backlog.dimensions["QueueName"] == "meridian-prod-budget-goods-received"
    error_message = "The backlog alarm must watch the queue, not the dead-letter queue."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.backlog.threshold < aws_sqs_queue.this.message_retention_seconds
    error_message = "The alarm must fire before messages are discarded at the end of retention."
  }
}

run "rejects_a_backlog_alarm_that_never_fires_in_time" {
  command = plan

  variables {
    backlog_alarm_minutes = 20000
  }

  expect_failures = [var.backlog_alarm_minutes]
}
