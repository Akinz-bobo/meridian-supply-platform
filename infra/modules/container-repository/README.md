# container-repository

A private ECR repository for one service's container images, with the policies to pull from it and to push to it.

Always on, whatever the caller passes:

| Protection | How |
| --- | --- |
| A tag means one image, for ever | Tags are immutable. A new build needs a new tag |
| Known vulnerabilities are found | Every image is scanned when it is pushed |
| Encrypted | With the customer managed key in `kms_key_arn` |
| Bounded | A lifecycle policy removes untagged leftovers after 7 days and keeps the newest 30 images |

What a caller needs to know:

- **One repository per service.** The pull policy then names one service's images.
- **Attach `pull_policy_json` to whatever runs the image**: the execution role of an ECS task, or the role of an EKS node. Attach `push_policy_json` to whatever builds. A pusher can add images and cannot delete one or change the repository.
- **Tag by content, not by `latest`.** With immutable tags a moving tag is impossible anyway. `make image` tags with a hash of the service's source, so the same source is pushed once and a tag always identifies one build.
- **`keep_tagged_images` bounds how far back a rollback can go.** It cannot be set below 5.
- **`force_delete`** is off by default. Only a disposable environment turns it on.

See [compute](../../../docs/architecture/compute.md#images).

<!-- BEGIN_TF_DOCS -->
## Usage

```hcl
module "context" {
  source = "../../../context"

  environment = "prod"
  component   = "catalog"
}

module "container_repository" {
  source = "../.."

  name       = module.context.prefix
  tags       = module.context.tags
  account_id = "333333333333"

  kms_key_arn = "arn:aws:kms:eu-west-1:333333333333:key/11111111-1111-1111-1111-111111111111"
}

# Attached to the execution role of the catalog service's tasks.
output "pull_policy_json" {
  description = "Policy that lets the catalog service's tasks pull its image."
  value       = module.container_repository.pull_policy_json
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
| account\_id | Account the repository is in. Used to name it exactly in the access policies. | `string` | n/a | yes |
| kms\_key\_arn | ARN of the key that encrypts images at rest. Pass the data key. | `string` | n/a | yes |
| name | Name of the repository, one per service. Build it from the context module's prefix. | `string` | n/a | yes |
| tags | Tags for the repository. Take them from the context module. | `map(string)` | n/a | yes |
| force\_delete | Let Terraform delete the repository while it still holds images. Turn on only in an environment whose data is disposable. | `bool` | `false` | no |
| keep\_tagged\_images | How many images to keep. Older ones are removed. It must be enough to roll back as far as you might need to. | `number` | `30` | no |
| untagged\_retention\_days | Days an image with no tag is kept. Untagged images are leftovers of interrupted pushes. | `number` | `7` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| pull\_policy\_json | IAM policy that lets a role pull images from this repository. Attach it to a task execution role or a node role. |
| push\_policy\_json | IAM policy that lets a role push images to this repository. It cannot delete an image or change the repository. Attach it to the role that builds. |
| repository\_arn | ARN of the repository. |
| repository\_name | Name of the repository. |
| repository\_url | Address to push to and pull from, without a tag. |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_ecr_lifecycle_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_lifecycle_policy) | resource |
| [aws_ecr_repository.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository) | resource |
| [aws_iam_policy_document.pull](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.push](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
<!-- END_TF_DOCS -->
