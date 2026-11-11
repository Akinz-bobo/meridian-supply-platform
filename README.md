# Meridian Supply Platform

A supply chain planning and operations platform for a distributor of perishable goods, built as a distributed system on AWS and defined entirely as code.

> **Status: in active development.** This repository is built in the open, milestone by milestone. The [milestones](https://github.com/Akinz-bobo/meridian-supply-platform/milestones) show what exists today and what is planned. Nothing here is described as done until it is merged and tested.

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

## Documentation

| Document                                               | What it covers                                                               |
| ------------------------------------------------------ | ---------------------------------------------------------------------------- |
| [Delivery process](docs/planning/delivery-process.md)  | How work moves from issue to merged pull request                             |
| [Decision records](docs/adr/README.md)                 | Why each significant choice was made                                         |
| [Domain model](docs/domain/domain-model.md)            | The business, its concepts, rules and lifecycles                             |
| [Glossary](docs/domain/glossary.md)                    | The words used here, with one meaning each                                   |
| [Architecture overview](docs/architecture/overview.md) | Context, services, data ownership, event flows and the AWS service catalogue |

More documents land through their own pull requests during the first milestone.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
