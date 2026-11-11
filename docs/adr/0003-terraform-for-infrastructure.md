# 0003: Use Terraform for infrastructure as code

|        |            |
| ------ | ---------- |
| Status | Accepted   |
| Date   | 2026-11-11 |
| Issue  | #5         |

## Context

Every resource in the platform must be declared in code, reviewed as a diff and applied by a pipeline. The tool chosen for that shapes the repository layout, the CI pipeline, the testing approach and the skills needed to work on it.

The requirements:

- reusable building blocks that can be composed into several environments
- a plan step that shows exactly what will change before it changes
- static analysis, security scanning and policy checks from mature tools
- a way to test modules
- works against the emulator chosen in [0002](0002-develop-against-an-aws-emulator.md)
- widely known, so the code is readable by most platform engineers

## Decision

Infrastructure is written in Terraform (HCL) using the official AWS provider. Kubernetes workloads on EKS are packaged as Helm charts and are not managed as Terraform resources: Terraform creates the cluster and what it depends on, and a GitOps controller owns what runs inside it.

Versions of Terraform and of every provider are pinned, and the dependency lock file is committed.

## Consequences

- One language and one workflow (`plan`, review, `apply`) for all cloud resources.
- A large ecosystem: tflint, security scanners, plan-based policy tools, `terraform test`, terraform-docs.
- State becomes a critical asset. It must be remote, encrypted, locked and backed up, which is its own piece of work in milestone 1.
- HCL is declarative and limited. Complex logic is awkward, which is mostly a benefit: it discourages clever infrastructure.
- Terraform is distributed under the Business Source License. That permits this use. OpenTofu is a compatible open-source fork, and the code avoids features that exist in only one of the two, so moving remains possible.
- Splitting Kubernetes workloads out of Terraform means two delivery mechanisms. The boundary is clear: Terraform stops at the cluster and its add-ons.

## Alternatives considered

- **AWS CloudFormation.** Native and needs no state management, but it is slower to iterate with, its modularity is weaker and its tooling ecosystem is smaller.
- **AWS CDK.** Real programming languages and good abstractions. It synthesises to CloudFormation and inherits its deployment model, and plans are harder to read in review than HCL diffs.
- **Pulumi.** Similar strengths to CDK with its own engine. Smaller pool of engineers who know it, and fewer policy and scanning tools.
- **OpenTofu.** A sound choice and nearly identical to work with. Terraform was chosen because it is what most teams and job descriptions name. The decision is cheap to revisit.
- **Managing Kubernetes resources with the Terraform Kubernetes provider.** Couples application rollout to infrastructure applies and makes the cluster a dependency of the plan. GitOps handles drift and rollout better.
