# permission-boundary

The managed policy that limits what any workload role in one environment can be allowed to do.

A permission boundary grants nothing. A role's effective permissions are the overlap of its own policies and its boundary. Attaching this one to every workload role means a wrong policy on a single role cannot reach another environment, another region or IAM.

What a caller needs to know:

- **Resources are matched by the naming standard**: names starting with `resource_prefix` and paths under `path_prefix`. The prefix must end with a hyphen and the path with a slash, or `meridian-prod` would also match `meridian-production`.
- **A workload cannot destroy history.** S3 actions are listed exactly: a workload may delete the current object, which with versioning leaves the old versions in place. Deleting a version, turning versioning off and changing lifecycle rules are denied outright.
- **No statement grants a whole service.** Actions are the data-plane actions workloads use: read and write objects, items, messages and events, read configuration and secrets, write logs.
- **Explicit denies sit on top** for IAM, key administration, object version deletion, audit log tampering and requests to other regions. They hold even if an allow is widened later.
- **Keys cannot be matched by name**, because key identifiers are random. The boundary allows use of keys in this account and region, and the role's own policy chooses which.
- **The output `policy_arn` is known at plan time.** It is built from the account and name, so policies that refer to the boundary can be rendered and policy checked before anything is applied.

The tests read the rendered policy JSON and fail if an allow statement uses a wildcard action, grants a whole service, or names a resource outside the environment. The model this fits into is in the [access model](../../../docs/architecture/access-model.md).

<!-- BEGIN_TF_DOCS -->
## Usage

```hcl
module "context" {
  source = "../../../context"

  environment = "prod"
  component   = "workload-boundary"
}

module "permission_boundary" {
  source = "../.."

  name            = module.context.prefix
  tags            = module.context.tags
  resource_prefix = "meridian-prod-"
  path_prefix     = "/meridian/prod/"
  account_id      = "333333333333"
  region          = "eu-west-1"
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
| account\_id | Account the boundary is for. Resources in any other account are outside it. | `string` | n/a | yes |
| name | Name of the boundary policy. Take it from the context module's prefix. | `string` | n/a | yes |
| path\_prefix | Path that every parameter, secret and log group of the environment lives under, including the trailing slash, for example /meridian/prod/. | `string` | n/a | yes |
| region | Region the environment is deployed to. Requests to any other region are denied. | `string` | n/a | yes |
| resource\_prefix | Prefix that every named resource of the environment starts with, including the trailing hyphen, for example meridian-prod-. | `string` | n/a | yes |
| tags | Tags for the policy. Take them from the context module. | `map(string)` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| policy\_arn | ARN of the boundary policy. Set it as permissions\_boundary on every workload role. |
| policy\_name | Name of the boundary policy. |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy_document.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
<!-- END_TF_DOCS -->
