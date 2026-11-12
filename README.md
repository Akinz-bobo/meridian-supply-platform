# Meridian Supply Platform

A supply chain planning and operations platform for a distributor of perishable goods, built as a distributed system on AWS and defined entirely as code.

> **Status: in active development.** This repository is built in the open, milestone by milestone. The [roadmap](docs/planning/roadmap.md) shows what exists today and what is planned. Nothing here is described as done until it is merged and tested.

## The problem

A regional distributor buys food and pharmaceutical products from dozens of suppliers and moves them through several warehouses. The goods carry batch numbers and expiry dates, and some need cold storage. The business runs into the same problems most distributors do:

- **Product data is a mess.** Every supplier sends a different spreadsheet. Nobody trusts the product master.
- **Stock is invisible.** Each warehouse knows its own shelves. Nobody sees the whole network.
- **Reordering is guesswork.** Buyers over-order slow lines and run out of fast ones, and stock expires on the shelf.
- **Spending is uncontrolled.** Purchase orders are raised without checking what is left in the budget.
- **There is no single view.** Management decisions wait on someone merging spreadsheets.

Meridian addresses each of these with a dedicated service, connected by events.

## What is being built

| Capability        | Service                                                               | Runs on                                |
| ----------------- | --------------------------------------------------------------------- | -------------------------------------- |
| Curation          | Catalog: ingest, validate, clean and approve supplier product data    | ECS Fargate, Step Functions, Lambda    |
| Supply chain      | Inventory: stock by warehouse and batch, movements, expiry            | EKS, DynamoDB                          |
| Operations        | Warehouse events: high-volume scanner events, fanned out to consumers | API Gateway, Lambda, Kinesis           |
| Supply chain      | Procurement: purchase orders, supplier lead times, receiving          | EKS, RDS                               |
| Planning          | Planning: demand forecast, reorder points, replenishment proposals    | ECS scheduled tasks, Step Functions    |
| Budgeting         | Budget: budgets, commitments against actuals, approvals               | EKS, RDS                               |
| Data presentation | Analytics: data lake, queries and dashboards                          | Firehose, S3, Glue, Athena, CloudFront |
| Integration       | ERP gateway: file exchange with a legacy finance system               | EC2, Systems Manager                   |

All of it sits on a three-tier network across three availability zones, with least-privilege IAM, encryption with KMS, audit logging and central observability. See the [architecture overview](docs/architecture/overview.md).

## Infrastructure as code

Every resource is declared in Terraform: reusable modules, composed into separate `dev`, `staging` and `production` environments, checked by linters, security scanners and policy rules on every pull request.

### Where it runs

The platform targets AWS. Day to day, and in CI, it is provisioned against [Floci](https://github.com/floci-io/floci), an open-source AWS emulator, so that anyone can clone the repository and stand the whole system up on a laptop with no AWS account and no bill.

That choice has limits, and they are stated plainly in [decision record 0002](docs/adr/0002-develop-against-an-aws-emulator.md): an emulator proves that the infrastructure code is valid and that the services work together. It does not prove production performance, real quotas or real cost.

## Try it

You need Docker, Terraform and the AWS CLI. No AWS account.

```bash
make tools    # install the pinned linter and scanner
make doctor   # check your tools
make up       # start the emulator
make bootstrap  # create the remote state bucket
make apply    # provision the dev environment's foundation layer
make destroy
make down     # stop and remove everything
```

See [local development](docs/guides/local-development.md).

## Documentation

| Document                                                              | What it covers                                                                                        |
| --------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| [Delivery process](docs/planning/delivery-process.md)                 | How work moves from issue to merged pull request                                                      |
| [Decision records](docs/adr/README.md)                                | Why each significant choice was made                                                                  |
| [Domain model](docs/domain/domain-model.md)                           | The business, its concepts, rules and lifecycles                                                      |
| [Glossary](docs/domain/glossary.md)                                   | The words used here, with one meaning each                                                            |
| [Architecture overview](docs/architecture/overview.md)                | Context, services, data ownership, event flows and the AWS service catalogue                          |
| [Event catalogue](docs/architecture/events.md)                        | Every planned event, its producer and its consumers                                                   |
| [Environments, naming and tagging](docs/architecture/environments.md) | How environments differ, the naming and tagging standard and the address plan                         |
| [Roadmap](docs/planning/roadmap.md)                                   | Milestones, their order, dependencies and status                                                      |
| [Local development](docs/guides/local-development.md)                 | Run the emulator on your machine: setup, commands, troubleshooting                                    |
| [Emulator differences](docs/architecture/emulator-differences.md)     | Where the emulator differs from AWS, and how each difference is handled                               |
| [Infrastructure guide](infra/README.md)                               | Terraform layout, commands, safety and how to add a layer                                             |
| [Runbook: Terraform state](docs/runbooks/terraform-state.md)          | Stuck locks, rolling state back, drift and losing the bootstrap state                                 |
| [Static analysis](docs/guides/static-analysis.md)                     | The checks that run before anything is provisioned, and how to handle a failure                       |
| [Policy as code](docs/guides/policy-as-code.md)                       | The organisation's rules, checked against every plan: tags, naming, regions, IAM, protected resources |
| [The infrastructure pipeline](docs/guides/pipeline.md)                | Plan and rehearsal on pull requests, apply on merge, and how it maps to real AWS                      |
| [Module standards](docs/architecture/module-standards.md)             | What every Terraform module looks like: layout, inputs, outputs, tests and generated documentation    |
| [Network](docs/architecture/network.md)                               | Tiers, address plan, routing and the reasons behind them                                              |

Changes are summarised in the [changelog](CHANGELOG.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
