# kms-key

A customer managed encryption key with an alias and a key policy.

What a caller needs to know:

- **Rotation is always on.** There is no input to turn it off. AWS replaces the key material yearly and keeps the old material, so existing data stays readable.
- **Deletion takes 30 days by default and never fewer than 14.** Deleting a key makes everything encrypted with it unreadable for good. The waiting period is the time to notice and cancel.
- **Access is delegated to IAM.** The key policy names the account root, which means a principal can use the key only when its own IAM policy allows it. Grant `kms:Decrypt` and `kms:GenerateDataKey` on the key's ARN to the roles that need them.
- **AWS services are named only when they must use the key themselves**, through `service_principals`, and each is limited to requests made on behalf of this account. CloudWatch Logs needs this. RDS, DynamoDB, S3 and Secrets Manager do not, because they use the key with the caller's permissions.
- **The rotation period is left to AWS's default of 365 days** unless `rotation_period_in_days` is set.

Which key encrypts what is in the [encryption standard](../../../docs/architecture/encryption.md), and why there are four keys per environment is in [decision record 0010](../../../docs/adr/0010-one-encryption-key-per-data-class.md).

<!-- BEGIN_TF_DOCS -->
## Usage

```hcl
module "context" {
  source = "../../../context"

  environment = "prod"
  component   = "logs"
}

module "kms_key" {
  source = "../.."

  name        = module.context.prefix
  tags        = module.context.tags
  description = "Encrypts CloudWatch log groups in production."
  account_id  = "333333333333"

  service_principals = ["logs.eu-west-1.amazonaws.com"]
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
| account\_id | Account that owns the key. Its IAM policies control who may use it. | `string` | n/a | yes |
| description | What the key protects, in one sentence. Shown in the console and in audit records. | `string` | n/a | yes |
| name | Name of the key, used as its alias: alias/<name>. Take it from the context module's prefix. | `string` | n/a | yes |
| tags | Tags for the key. Take them from the context module. | `map(string)` | n/a | yes |
| deletion\_window\_in\_days | Days between scheduling the key for deletion and its deletion. Deletion makes everything encrypted with the key unreadable, and this is the time to notice. | `number` | `30` | no |
| rotation\_period\_in\_days | How often AWS replaces the key material, in days. With null, AWS uses its default of 365. Old material is kept, so existing data stays readable. | `number` | `null` | no |
| service\_principals | AWS services allowed to use the key for this account, for example logs.eu-west-1.amazonaws.com. | `set(string)` | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| alias\_arn | ARN of the alias. IAM policies can grant use of a key by alias. |
| alias\_name | Alias of the key, including the alias/ prefix. |
| key\_arn | ARN of the key. Use this wherever a resource asks for a KMS key. |
| key\_id | Identifier of the key. |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_kms_alias.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_iam_policy_document.key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
<!-- END_TF_DOCS -->
