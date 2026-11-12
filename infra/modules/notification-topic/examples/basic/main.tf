module "context" {
  source = "../../../context"

  environment = "prod"
  component   = "alarms"
}

module "notification_topic" {
  source = "../.."

  name         = module.context.prefix
  tags         = module.context.tags
  display_name = "Meridian alarms"
  account_id   = "333333333333"

  kms_key_arn = "arn:aws:kms:eu-west-1:333333333333:key/55555555-5555-5555-5555-555555555555"

  # CloudWatch publishes alarm state changes as the service.
  publishing_services = ["cloudwatch.amazonaws.com"]

  subscriptions = {
    oncall = { protocol = "email", endpoint = "oncall@example.com" }
  }
}
