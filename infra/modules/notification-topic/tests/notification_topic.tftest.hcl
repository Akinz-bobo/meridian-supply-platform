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
  name                = "meridian-prod-alarms"
  account_id          = "333333333333"
  kms_key_arn         = "arn:aws:kms:eu-west-1:333333333333:key/55555555-5555-5555-5555-555555555555"
  publishing_services = ["cloudwatch.amazonaws.com"]
  tags = {
    Project = "meridian"
  }
}

run "encrypts_messages_with_the_given_key" {
  command = plan

  assert {
    condition     = aws_sns_topic.this.kms_master_key_id == "arn:aws:kms:eu-west-1:333333333333:key/55555555-5555-5555-5555-555555555555"
    error_message = "The topic must use the key that was passed."
  }
}

run "admits_only_the_named_services_for_this_account" {
  command = plan

  assert {
    condition = one([
      for statement in jsondecode(data.aws_iam_policy_document.topic.json).Statement : statement
      if statement.Sid == "NamedServicesPublishForThisAccount"
    ]).Principal.Service == "cloudwatch.amazonaws.com"
    error_message = "Only the named service may publish."
  }

  assert {
    condition = one([
      for statement in jsondecode(data.aws_iam_policy_document.topic.json).Statement : statement
      if statement.Sid == "NamedServicesPublishForThisAccount"
    ]).Condition.StringEquals["aws:SourceAccount"] == "333333333333"
    error_message = "A service may publish only on behalf of this account."
  }
}

run "no_allow_statement_admits_everyone" {
  command = plan

  assert {
    condition = alltrue([
      for statement in jsondecode(data.aws_iam_policy_document.topic.json).Statement :
      statement.Effect == "Deny" || try(statement.Principal.Service, null) != null
    ])
    error_message = "Every allow statement must name a service. None may admit any principal."
  }
}

run "refuses_publishing_without_tls" {
  command = plan

  assert {
    condition = one([
      for statement in jsondecode(data.aws_iam_policy_document.topic.json).Statement : statement
      if statement.Sid == "DenyInsecureTransport"
    ]).Condition.Bool["aws:SecureTransport"] == "false"
    error_message = "The topic policy must deny publishing that does not use TLS."
  }
}

run "nothing_outside_the_account_can_subscribe" {
  command = plan

  assert {
    condition = one([
      for statement in jsondecode(data.aws_iam_policy_document.topic.json).Statement : statement
      if statement.Sid == "OnlyThisAccountSubscribes"
    ]).Condition.StringNotEquals["aws:PrincipalAccount"] == "333333333333"
    error_message = "Subscribing from another account must be denied."
  }
}

run "a_topic_with_no_services_has_no_allow_statement" {
  command = plan

  variables {
    publishing_services = []
  }

  assert {
    condition     = alltrue([for statement in jsondecode(data.aws_iam_policy_document.topic.json).Statement : statement.Effect == "Deny"])
    error_message = "With no publishing services the topic policy only denies. Roles publish through IAM."
  }
}

run "a_role_can_publish_to_this_topic_only" {
  command = plan

  assert {
    condition     = jsondecode(output.publish_policy_json).Statement[0].Resource == "arn:aws:sns:eu-west-1:333333333333:meridian-prod-alarms" && jsondecode(output.publish_policy_json).Statement[0].Action == "sns:Publish"
    error_message = "The publish policy names this topic and the publish action."
  }
}

run "adds_subscriptions" {
  command = plan

  variables {
    subscriptions = {
      inbox = { protocol = "sqs", endpoint = "arn:aws:sqs:eu-west-1:333333333333:meridian-prod-alarms-inbox", raw_message_delivery = true }
      team  = { protocol = "email", endpoint = "oncall@example.com" }
    }
  }

  assert {
    condition     = aws_sns_topic_subscription.this["inbox"].raw_message_delivery == true
    error_message = "A queue subscription can take the message without the SNS wrapper."
  }

  assert {
    condition     = aws_sns_topic_subscription.this["team"].protocol == "email"
    error_message = "Each subscription keeps its protocol."
  }
}

run "rejects_delivery_over_plain_http" {
  command = plan

  variables {
    subscriptions = {
      hook = { protocol = "http", endpoint = "http://example.com/hook" }
    }
  }

  expect_failures = [var.subscriptions]
}

run "rejects_a_principal_that_is_not_a_service" {
  command = plan

  variables {
    publishing_services = ["*"]
  }

  expect_failures = [var.publishing_services]
}

run "rejects_a_topic_without_a_customer_managed_key" {
  command = plan

  variables {
    kms_key_arn = ""
  }

  expect_failures = [var.kms_key_arn]
}
