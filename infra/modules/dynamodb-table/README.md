# dynamodb-table

A DynamoDB table with the IAM policies that let a workload read it, write it or consume its change stream.

Always on, whatever the caller passes:

| Protection | How |
| --- | --- |
| Encrypted | Server-side encryption with the customer managed key in `kms_key_arn` |
| Recoverable | Point-in-time recovery, to any second of the last 35 days |
| Classified | `data_classification` is required and becomes the `DataClassification` tag |

On by default, and an input:

| Protection | Input |
| --- | --- |
| Cannot be deleted | `deletion_protection`. Turned off only where the environment is disposable |

What a caller decides:

- **Keys and indexes.** `hash_key`, `range_key`, `global_secondary_indexes`, and the type of every key attribute in `attributes`. The module refuses a key whose type is not declared, and a declared attribute that is not a key, at plan time. DynamoDB would reject both at apply with a less helpful message.
- **Capacity.** Billed per request by default, which suits traffic that is low or hard to predict. `provisioned_capacity` switches to a range that autoscaling moves within, for the table and for every index.
- **Expiry.** `ttl_attribute` names the attribute that holds an item's expiry time.
- **Change stream.** `stream_view_type` turns on a stream of item changes.

What a caller needs to know:

- **Use the policy outputs.** `read_policy_json`, `write_policy_json`, `append_policy_json` and `stream_policy_json` are attached to workload roles. All four tie use of the shared data key to this table through the encryption context.
- **The read policy has no `Scan`.** A scan reads the whole table and is billed for all of it. An access pattern that needs one needs an index. A caller who truly wants a scan adds the statement explicitly, where a reviewer will see it.
- **`append_policy_json` is for a table that is a record.** It can add and read items, and cannot update or delete one. The movement ledger uses it. Whether an add may replace an existing item is decided by the writer's condition expression, and a ledger writes with `attribute_not_exists`.
- **The write policy is for items.** It cannot update, delete or back up the table.
- **Transactions need no action of their own.** DynamoDB authorises `TransactWriteItems` by the item actions inside it, so none of the policies names it.
- **Index keys use `key_schema` blocks.** The provider deprecated `hash_key` and `range_key` on indexes.

The key design of the inventory tables, and a check that exercises it, are in the [inventory data model](../../../docs/architecture/inventory-data-model.md).

<!-- BEGIN_TF_DOCS -->
## Usage

```hcl
module "context" {
  source = "../../../context"

  environment = "prod"
  component   = "inventory"
}

# An append-only ledger: one item per stock movement, grouped by batch, with
# an index that lists a warehouse's movements for a day.
module "dynamodb_table" {
  source = "../.."

  name       = "${module.context.prefix}-movements"
  tags       = module.context.tags
  account_id = "333333333333"

  data_classification = "internal"
  kms_key_arn         = "arn:aws:kms:eu-west-1:333333333333:key/11111111-2222-3333-4444-555555555555"

  hash_key  = "pk"
  range_key = "sk"
  attributes = {
    pk     = "S"
    sk     = "S"
    gsi1pk = "S"
    gsi1sk = "S"
  }

  global_secondary_indexes = [
    { name = "by-warehouse-day", hash_key = "gsi1pk", range_key = "gsi1sk" },
  ]

  # Every new movement is streamed to the analytics pipeline.
  stream_view_type = "NEW_IMAGE"
}

# Attached to the inventory service's role.
output "write_policy_json" {
  description = "Policy for the inventory service's role."
  value       = module.dynamodb_table.write_policy_json
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
| account\_id | Account the table is in. Used to name the table exactly in the access policies. | `string` | n/a | yes |
| attributes | Type of every attribute used in a key of the table or of an index: S (string), N (number) or B (binary). Attributes that are not part of a key are not declared. | `map(string)` | n/a | yes |
| data\_classification | How sensitive the contents are: public, internal, confidential or restricted. Becomes the DataClassification tag. | `string` | n/a | yes |
| hash\_key | Name of the partition key attribute. | `string` | n/a | yes |
| kms\_key\_arn | ARN of the key that encrypts the table. Pass the data key. | `string` | n/a | yes |
| name | Name of the table. Build it from the context module's prefix. | `string` | n/a | yes |
| tags | Tags for the table. Take them from the context module. | `map(string)` | n/a | yes |
| deletion\_protection | Refuse to delete the table. Turn off only in an environment whose data is disposable. | `bool` | `true` | no |
| global\_secondary\_indexes | Indexes that give the table further access patterns. projection\_type is ALL, KEYS\_ONLY or INCLUDE, and INCLUDE needs non\_key\_attributes. | <pre>list(object({<br/>    name               = string<br/>    hash_key           = string<br/>    range_key          = optional(string)<br/>    projection_type    = optional(string, "ALL")<br/>    non_key_attributes = optional(list(string), [])<br/>  }))</pre> | `[]` | no |
| provisioned\_capacity | Pay for a fixed range of capacity that autoscaling moves within, for the table and every index. With null the table is billed per request, which suits unpredictable or low traffic. | <pre>object({<br/>    read_min           = number<br/>    read_max           = number<br/>    write_min          = number<br/>    write_max          = number<br/>    target_utilization = optional(number, 70)<br/>  })</pre> | `null` | no |
| range\_key | Name of the sort key attribute. With null the table has a partition key only. | `string` | `null` | no |
| store\_tags | Extra tags for the table only, and not for the resources around it. Use it for the tag that opts the store in to a backup plan. | `map(string)` | `{}` | no |
| stream\_view\_type | Stream item changes, with this content: KEYS\_ONLY, NEW\_IMAGE, OLD\_IMAGE or NEW\_AND\_OLD\_IMAGES. With null there is no stream. | `string` | `null` | no |
| ttl\_attribute | Attribute holding the time, in seconds since the epoch, after which an item is deleted. With null, items never expire. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| append\_policy\_json | IAM policy that lets a role add and read items, and never update or delete one. For a table that is a record, such as a ledger. Attach it to a workload role. |
| read\_policy\_json | IAM policy that lets a role read items, by key or through an index. Scans are not included. Attach it to a workload role. |
| stream\_arn | ARN of the change stream. Null when the table has no stream. |
| stream\_policy\_json | IAM policy that lets a role consume the table's change stream. Attach it to the role of a stream consumer. |
| table\_arn | ARN of the table. |
| table\_name | Name of the table. |
| write\_policy\_json | IAM policy that lets a role read and write items. It cannot change or delete the table. Attach it to a workload role. |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_appautoscaling_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_policy) | resource |
| [aws_appautoscaling_target.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_target) | resource |
| [aws_dynamodb_table.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table) | resource |
| [aws_iam_policy_document.append](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.read](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.stream](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.write](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
<!-- END_TF_DOCS -->
