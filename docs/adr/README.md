# Architecture decision records

A decision record captures one significant choice: the situation, what was decided, what it costs and what else was considered. Records are short, numbered and never deleted. A decision that is reversed gets a new record that supersedes the old one, so the reasoning at each point in time stays readable.

Write a record when a choice is expensive to reverse, when it constrains later work, or when a reasonable engineer would ask "why did they do it this way?".

Start from the [template](template.md).

## Index

| Number                                          | Decision                                                          | Status   |
| ----------------------------------------------- | ----------------------------------------------------------------- | -------- |
| [0001](0001-record-architecture-decisions.md)   | Record architecture decisions                                     | Accepted |
| [0002](0002-develop-against-an-aws-emulator.md) | Develop and test against an AWS emulator                          | Accepted |
| [0003](0003-terraform-for-infrastructure.md)    | Use Terraform for infrastructure as code                          | Accepted |
| [0004](0004-single-repository.md)               | Keep infrastructure, services and documentation in one repository | Accepted |
| [0005](0005-compute-model-per-workload.md)      | Choose the compute model per workload by a stated rule            | Accepted |
