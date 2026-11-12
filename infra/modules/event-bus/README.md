# event-bus

The EventBridge bus that carries business events between services, with its archive, a log of every event, and a publish policy for each producer.

What a caller needs to know:

- **A producer can publish only as itself.** `publishers` lists the services that publish. Each gets a policy in `publish_policy_json` that allows `events:PutEvents` only when the event's source is `<source_prefix>.<publisher>`. The catalog service cannot put an event on the bus that claims to come from procurement.
- **Nothing outside the account can publish**, whatever IAM policy anyone writes. The bus policy denies it.
- **Every event is archived**, for 90 days by default, so that a consumer added later or one that lost data can be sent the past again.
- **Every event is logged** to `/aws/events/<name>`, encrypted and with retention. During an incident, "was it published, and what did it say" is a log query, with no replay needed.
- **The bus is encrypted** with the key in `kms_key_arn`. A publisher's policy includes use of that key, only by way of EventBridge.
- **Consumers are not here.** A consumer gets its own queue, fed by its own rule on this bus, from the `event-consumer-queue` module.

The shape of an event is in the [event contracts](../../../contracts/events/README.md), and the conventions are in [decision record 0006](../../../docs/adr/0006-event-backbone-and-messaging-conventions.md).

<!-- BEGIN_TF_DOCS -->
## Usage

```hcl
module "context" {
  source = "../../../context"

  environment = "prod"
  component   = "events"
}

module "event_bus" {
  source = "../.."

  name = module.context.prefix
  tags = module.context.tags

  account_id    = "333333333333"
  source_prefix = "meridian"
  publishers    = ["catalog", "inventory", "procurement"]

  kms_key_arn      = "arn:aws:kms:eu-west-1:333333333333:key/55555555-5555-5555-5555-555555555555"
  logs_kms_key_arn = "arn:aws:kms:eu-west-1:333333333333:key/33333333-3333-3333-3333-333333333333"
}

# Attached to the catalog service's role. It can publish as meridian.catalog
# and as nothing else.
output "catalog_publish_policy_json" {
  description = "Policy that lets the catalog service publish its events."
  value       = module.event_bus.publish_policy_json["catalog"]
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
| account\_id | Account the bus is in. Nothing outside it can publish. | `string` | n/a | yes |
| kms\_key\_arn | ARN of the key that encrypts events on the bus and in the archive. Pass the messaging key. | `string` | n/a | yes |
| logs\_kms\_key\_arn | ARN of the key that encrypts the event log group. Pass the logs key. | `string` | n/a | yes |
| name | Name of the bus, and the prefix of its archive, rule and log group. Build it from the context module's prefix. | `string` | n/a | yes |
| source\_prefix | First part of every event's source. A publisher called procurement publishes as <source\_prefix>.procurement. | `string` | n/a | yes |
| tags | Tags for every resource in the module. Take them from the context module. | `map(string)` | n/a | yes |
| archive\_retention\_days | How long events are kept for replay. | `number` | `90` | no |
| description | What travels on the bus, in one sentence. | `string` | `"Business events between the platform's services."` | no |
| log\_retention\_days | How long the readable log of events is kept. | `number` | `30` | no |
| publishers | Services that publish to the bus, by the name used in their source. Each gets a publish policy limited to that source. | `set(string)` | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| archive\_arn | ARN of the archive, for starting a replay. |
| bus\_arn | ARN of the bus. |
| bus\_name | Name of the bus. Producers put events on it, and consumer rules attach to it. |
| log\_group\_name | Log group that holds a readable copy of every event. |
| publish\_policy\_json | IAM policy for each publisher, keyed by its name. It lets a role put events on the bus under that service's source and no other. Attach it to the service's workload role. |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_event_archive.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_archive) | resource |
| [aws_cloudwatch_event_bus.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_bus) | resource |
| [aws_cloudwatch_event_bus_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_bus_policy) | resource |
| [aws_cloudwatch_event_rule.log](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule) | resource |
| [aws_cloudwatch_event_target.log](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) | resource |
| [aws_cloudwatch_log_group.events](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_resource_policy.events](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_resource_policy) | resource |
| [aws_iam_policy_document.bus](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.log_delivery](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.publish](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
<!-- END_TF_DOCS -->
