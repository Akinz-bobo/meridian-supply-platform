# notification-topic

An SNS topic for telling people, or their tools, that something happened: an alarm changed state, or an event occurred that someone needs to know about.

What a caller needs to know:

- **Encrypted** with the key in `kms_key_arn`, and **TLS only**: the topic policy denies publishing over a plain connection.
- **AWS services publish as the service, not as a role**, so they are named in `publishing_services` and admitted by the topic policy, each limited to this account: `cloudwatch.amazonaws.com` for alarms, `events.amazonaws.com` for rules on the bus. The same service must be named in the key policy of the key, or its messages are refused at encryption.
- **Roles publish through IAM.** Attach `publish_policy_json` to a workload role that needs to publish.
- **Nothing outside the account can subscribe.** A subscription decides where messages go, so adding one is restricted.
- **Subscriptions over plain `http` are refused.** They would send the message unencrypted.
- **Who is subscribed is an input**, and is usually different in every environment. An email subscription must be confirmed by its recipient before anything is delivered.

See [messaging](../../../docs/architecture/messaging.md).

<!-- BEGIN_TF_DOCS -->
## Usage

```hcl
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
```

## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.10.0, < 2.0.0 |
| aws | >= 6.0 |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| account\_id | Account the topic is in. Only this account's services and principals may publish or subscribe. | `string` | n/a | yes |
| kms\_key\_arn | ARN of the key that encrypts messages in the topic. Pass the messaging key. | `string` | n/a | yes |
| name | Name of the topic. Build it from the context module's prefix. | `string` | n/a | yes |
| tags | Tags for the topic. Take them from the context module. | `map(string)` | n/a | yes |
| display\_name | Name shown as the sender of an email or text message. | `string` | `null` | no |
| publishing\_services | AWS services allowed to publish to the topic for this account, for example cloudwatch.amazonaws.com for alarms and events.amazonaws.com for rules on the bus. Each must also be named in the key policy of the key. | `set(string)` | `[]` | no |
| subscriptions | Where messages are delivered, keyed by a short name. protocol is one of email, https, sqs, lambda, sms or firehose. | <pre>map(object({<br/>    protocol             = string<br/>    endpoint             = string<br/>    raw_message_delivery = optional(bool, false)<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| publish\_policy\_json | IAM policy that lets a role publish to the topic. Attach it to a workload role. |
| topic\_arn | ARN of the topic. Use it as an alarm action or a rule target. |
| topic\_name | Name of the topic. |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_sns_topic.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic) | resource |
| [aws_sns_topic_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_policy) | resource |
| [aws_sns_topic_subscription.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription) | resource |
| [aws_iam_policy_document.publish](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.topic](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
<!-- END_TF_DOCS -->
