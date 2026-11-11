# state-bucket

The S3 bucket that holds Terraform state for every environment.

State lists every resource and can contain secrets, so the protections below are always on and a caller cannot turn them off:

| Protection | How |
| --- | --- |
| Private | All four public access block settings, and ACLs disabled |
| Encrypted | Its own customer managed KMS key, with rotation |
| Recoverable | Versioning, with old versions kept for 90 days by default and never fewer than 30 |
| Transport | A bucket policy that denies any request not made over TLS |
| No plain uploads | A bucket policy that denies uploads not encrypted with KMS |
| Hard to delete | `force_destroy` is off by default |

Locking uses a lock object in the same bucket (the S3 backend's `use_lockfile`), so there is no lock table. The design is in [decision record 0009](../../../docs/adr/0009-remote-state-in-s3-with-native-locking.md), and recovery procedures are in the [state runbook](../../../docs/runbooks/terraform-state.md).

<!-- BEGIN_TF_DOCS -->
## Usage

```hcl
module "context" {
  source = "../../../context"

  environment = "shared"
  component   = "tfstate"
}

module "state_bucket" {
  source = "../.."

  # Bucket names are global, so include the account and region.
  name = "${module.context.prefix}-444444444444-eu-west-1"
  tags = module.context.tags
}

output "bucket" {
  description = "Use this as the bucket in the S3 backend configuration."
  value       = module.state_bucket.bucket
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
| name | Bucket name. Must be globally unique, so include the account id and region. | `string` | n/a | yes |
| tags | Tags for every resource in the module. | `map(string)` | n/a | yes |
| force\_destroy | Allow the bucket to be destroyed while it still holds state. Only for throwaway environments. | `bool` | `false` | no |
| kms\_deletion\_window\_days | Waiting period before the encryption key is destroyed after deletion is requested. | `number` | `30` | no |
| noncurrent\_version\_retention\_days | How long a replaced state version is kept before it is deleted. | `number` | `90` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| bucket | Name of the state bucket. |
| bucket\_arn | ARN of the state bucket. |
| kms\_key\_alias | Alias of the key that encrypts state. |
| kms\_key\_arn | ARN of the key that encrypts state. |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_kms_alias.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_s3_bucket.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_ownership_controls.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_iam_policy_document.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
<!-- END_TF_DOCS -->
