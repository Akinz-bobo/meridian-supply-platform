# context

Naming and tagging in one place.

Every other module takes its names and tags from this one, so the [naming and tagging standard](../../../docs/architecture/environments.md#naming-standard) is enforced by construction and never re-implemented by string concatenation in a resource. The module creates nothing and needs no provider.

- `prefix` is `<project>-<environment>-<component>`. Append a qualifier to tell sibling resources apart.
- `tags` is the standard tag set. A caller can add tags but cannot override a standard one.
- `ssm_path` is the component's path in Parameter Store.

<!-- BEGIN_TF_DOCS -->
## Usage

```hcl
module "context" {
  source = "../.."

  environment = "prod"
  component   = "inventory"

  extra_tags = {
    DataClassification = "confidential"
  }
}

# Take every name and tag from the module. Append a qualifier to the prefix
# to tell sibling resources apart.
output "queue_name" {
  description = "meridian-prod-inventory-movements"
  value       = "${module.context.prefix}-movements"
}

output "tags" {
  description = "The standard tags plus DataClassification."
  value       = module.context.tags
}
```

## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.9.0, < 2.0.0 |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| component | Service or building block that owns the resources, in kebab case. For example: network, inventory. | `string` | n/a | yes |
| environment | Environment the resources belong to. `shared` is the shared-services account. | `string` | n/a | yes |
| cost\_centre | Cost allocation label. | `string` | `"supply-chain"` | no |
| extra\_tags | Additional tags. They cannot override the standard tags. | `map(string)` | `{}` | no |
| owner | Team responsible for the resources. | `string` | `"platform"` | no |
| project | Short name of the platform. First part of every resource name. | `string` | `"meridian"` | no |
| repository | Repository that defines the resources. | `string` | `"Akinz-bobo/meridian-supply-platform"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| environment | The environment, passed through for convenience. |
| prefix | Name prefix: <project>-<environment>-<component>. Append a qualifier for sibling resources. |
| ssm\_path | Parameter Store path for this component: /<project>/<environment>/<component>. |
| tags | Standard tags, plus any extra tags that do not collide with them. |

<!-- END_TF_DOCS -->
