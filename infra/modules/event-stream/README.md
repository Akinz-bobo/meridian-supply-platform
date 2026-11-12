# event-stream

A Kinesis stream: an ordered, replayable log of records, with separate policies for the roles that write to it and the roles that read from it.

What a caller needs to know:

- **Order is per partition key.** Records written with the same key go to the same shard and are read in the order they were written. Records with different keys have no order between them. Choose the key to be the thing whose history must stay in order.
- **Several consumers read independently**, each at its own position, and each can go back and read again for as long as `retention_hours` allows. A consumer that is down for longer than that loses records, so set it to more than the longest outage you intend to survive.
- **On demand by default.** The stream scales its own shards, which suits traffic that arrives in bursts. `shard_count` fixes the capacity when the load is steady and known.
- **Always encrypted** with the key in `kms_key_arn`.
- **A producer cannot read and a consumer cannot write.** Attach `produce_policy_json` or `consume_policy_json` to a workload role. Both tie use of the key to this stream through the encryption context.
- **Metrics are per shard.** The stream-level average hides a hot shard, which is the sign of one partition key carrying too much.
- **A stream is not the bus.** Use it when order or volume demands it. Business events between services go over the event bus, where a consumer has a queue with retries and a dead-letter queue.

See [messaging](../../../docs/architecture/messaging.md#the-movement-stream).

<!-- BEGIN_TF_DOCS -->
## Usage

```hcl
module "context" {
  source = "../../../context"

  environment = "prod"
  component   = "inventory"
}

module "event_stream" {
  source = "../.."

  name       = "${module.context.prefix}-movement-stream"
  tags       = module.context.tags
  account_id = "333333333333"

  data_classification = "internal"
  kms_key_arn         = "arn:aws:kms:eu-west-1:333333333333:key/55555555-5555-5555-5555-555555555555"

  # Long enough for the inventory service to be down over a weekend and
  # still catch up.
  retention_hours = 72
}

# Attached to the scan intake function's role.
output "produce_policy_json" {
  description = "Policy that lets scan intake write movements."
  value       = module.event_stream.produce_policy_json
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
| account\_id | Account the stream is in. Used to name it exactly in the access policies. | `string` | n/a | yes |
| data\_classification | How sensitive the records are: public, internal, confidential or restricted. Becomes the DataClassification tag. | `string` | n/a | yes |
| kms\_key\_arn | ARN of the key that encrypts records in the stream. Pass the messaging key. | `string` | n/a | yes |
| name | Name of the stream. Build it from the context module's prefix. | `string` | n/a | yes |
| tags | Tags for the stream. Take them from the context module. | `map(string)` | n/a | yes |
| retention\_hours | How long records can be read, and read again. A consumer that is down for longer than this loses records. | `number` | `48` | no |
| shard\_count | Fixed number of shards. With null the stream is on demand and scales its own shards, which suits traffic that arrives in bursts. | `number` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| consume\_policy\_json | IAM policy that lets a role read records from the stream. It cannot write to it. Attach it to a consumer's workload role. |
| produce\_policy\_json | IAM policy that lets a role write records to the stream. It cannot read them. Attach it to a producer's workload role. |
| stream\_arn | ARN of the stream. |
| stream\_name | Name of the stream. |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_kinesis_stream.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kinesis_stream) | resource |
| [aws_iam_policy_document.consume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.produce](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
<!-- END_TF_DOCS -->
