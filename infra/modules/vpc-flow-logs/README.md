# vpc-flow-logs

Records the traffic of a VPC in a CloudWatch log group: the log group, the flow log, and the role the flow logs service uses to write.

What a caller needs to know:

- **All traffic is recorded by default**, accepted and rejected. Rejected traffic alone shows what was blocked and hides what got through.
- **Logs are kept for 90 days by default and never fewer than 30.** A shorter period is refused at plan time.
- **The delivery role is narrow.** It can create streams and put events in this one log group. Its trust policy admits only the flow logs service acting for the given account, which closes the confused deputy path.
- **Encryption with a customer managed key is opt-in through `kms_key_arn`.** The environment passes its logs key once the keys from the encryption standard exist. Without it CloudWatch encrypts with a key it owns.

It is a separate module from [`vpc`](../vpc/README.md) so that where logs go and how long they are kept can change without a plan that touches the network.

<!-- BEGIN_TF_DOCS -->
## Usage

```hcl
module "context" {
  source = "../../../context"

  environment = "prod"
  component   = "network"
}

module "vpc_flow_logs" {
  source = "../.."

  name           = module.context.prefix
  tags           = module.context.tags
  vpc_id         = "vpc-0123456789abcdef0"
  account_id     = "333333333333"
  log_group_name = "/meridian/prod/network/flow-logs"
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
| account\_id | Account the VPC is in. The delivery role can be assumed only on behalf of this account. | `string` | n/a | yes |
| log\_group\_name | Name of the log group, a path under /<project>/<environment>/. | `string` | n/a | yes |
| name | Prefix for the role and the flow log. Take it from the context module's prefix. | `string` | n/a | yes |
| tags | Tags for every resource in the module. Take them from the context module. | `map(string)` | n/a | yes |
| vpc\_id | Identifier of the VPC to record. | `string` | n/a | yes |
| kms\_key\_arn | Customer managed key that encrypts the log group. With null, CloudWatch encrypts with a key it owns. | `string` | `null` | no |
| max\_aggregation\_interval | Seconds over which a flow is aggregated into one record: 60 or 600. | `number` | `60` | no |
| retention\_in\_days | How long flow logs are kept. | `number` | `90` | no |
| traffic\_type | Which traffic to record: ALL, ACCEPT or REJECT. | `string` | `"ALL"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| flow\_log\_id | Identifier of the flow log. |
| log\_group\_arn | ARN of the log group that receives the flow logs. |
| log\_group\_name | Name of the log group that receives the flow logs. |
| role\_arn | ARN of the role the flow logs service uses to write to the log group. |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_flow_log.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/flow_log) | resource |
| [aws_iam_role.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_policy_document.assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.deliver](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
<!-- END_TF_DOCS -->
