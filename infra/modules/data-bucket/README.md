# data-bucket

A private, encrypted, versioned S3 bucket for the platform's data, with the IAM policies that let a workload read or write it.

Always on, whatever the caller passes:

| Protection | How |
| --- | --- |
| Private | All four public access block settings, and ACLs disabled |
| Encrypted | Default encryption with the customer managed key in `kms_key_arn`, with a bucket key |
| Only that key | The bucket policy denies an upload that names another key or another encryption method |
| Transport | The bucket policy denies any request not made over TLS |
| Recoverable | Versioning. Old versions are kept for 90 days by default and never fewer than 7 |
| Classified | `data_classification` is required and becomes the `DataClassification` tag |

What a caller decides:

- **Retention.** `expiration_days` deletes objects after a time. Without it they are kept until something deletes them.
- **Storage class.** `transitions` moves objects to cheaper storage as they age.
- **Events.** `eventbridge_notifications` sends every object event to the event bus, where rules decide who hears about it. The bucket never notifies a consumer directly.
- **`force_destroy`.** Off by default. Only a disposable environment turns it on.

What a caller needs to know:

- **Use the policy outputs.** `read_policy_json` and `write_policy_json` are attached to a service's workload role. Both tie use of the key to objects in this bucket through the encryption context, so a role given this bucket cannot use the shared data key to decrypt another store. `write_policy_json` can delete the current object and cannot delete versions, change the bucket policy or change lifecycle rules.
- **Bucket names are global.** Build the name from the context prefix plus the account id and region.
- **The policies are known at plan time**, because the bucket ARN is built from its name. They can therefore be policy checked before the bucket exists.

Which bucket holds what is in the [data architecture](../../../docs/architecture/data.md).

<!-- BEGIN_TF_DOCS -->
## Usage

```hcl
module "context" {
  source = "../../../context"

  environment = "prod"
  component   = "catalog"
}

module "data_bucket" {
  source = "../.."

  name = "${module.context.prefix}-uploads-333333333333-eu-west-1"
  tags = module.context.tags

  data_classification = "confidential"
  kms_key_arn         = "arn:aws:kms:eu-west-1:333333333333:key/11111111-2222-3333-4444-555555555555"

  # Supplier files are kept for a year, in cheaper storage after 90 days.
  expiration_days = 365
  transitions     = [{ days = 90, storage_class = "STANDARD_IA" }]

  # Tell the event bus when a supplier uploads a file.
  eventbridge_notifications = true
}

# Attached to the role of the service that reads and writes the bucket.
output "write_policy_json" {
  description = "Policy for the curation workflow's role."
  value       = module.data_bucket.write_policy_json
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
| data\_classification | How sensitive the contents are: public, internal, confidential or restricted. Becomes the DataClassification tag. | `string` | n/a | yes |
| kms\_key\_arn | ARN of the key that encrypts the bucket. Pass the data key. | `string` | n/a | yes |
| name | Name of the bucket. Bucket names are global, so build it from the context module's prefix plus the account id and region. | `string` | n/a | yes |
| tags | Tags for the bucket. Take them from the context module. | `map(string)` | n/a | yes |
| eventbridge\_notifications | Send an event to EventBridge for every object created, deleted or restored. Rules on the bus then decide who hears about it. | `bool` | `false` | no |
| expiration\_days | Delete objects this many days after they are created. With null, objects are kept until something deletes them. | `number` | `null` | no |
| force\_destroy | Let Terraform delete the bucket while it still contains objects. Leave off anywhere the data matters. | `bool` | `false` | no |
| noncurrent\_version\_retention\_days | How long a replaced or deleted version of an object is kept before it is removed for good. | `number` | `90` | no |
| transitions | Moves to cheaper storage as objects age, in order. Each entry is a number of days after creation and a storage class. | <pre>list(object({<br/>    days          = number<br/>    storage_class = string<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| bucket\_arn | ARN of the bucket. |
| bucket\_name | Name of the bucket. |
| read\_policy\_json | IAM policy that lets a role list the bucket and read and decrypt its objects. Attach it to a workload role. |
| write\_policy\_json | IAM policy that lets a role read, write and delete current objects. It cannot delete versions or change the bucket. Attach it to a workload role. |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_s3_bucket.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_notification.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_notification) | resource |
| [aws_s3_bucket_ownership_controls.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_iam_policy_document.bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.read](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.write](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
<!-- END_TF_DOCS -->
