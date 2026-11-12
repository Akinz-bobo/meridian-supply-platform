# Infrastructure

Everything the platform runs on, as Terraform. The reasoning behind the layout is in decision records [0003](../docs/adr/0003-terraform-for-infrastructure.md), [0007](../docs/adr/0007-environments-and-account-isolation.md) and [0008](../docs/adr/0008-layered-state-per-environment.md).

## Layout

```
infra/
  bootstrap/         creates the remote state bucket. Applied once, by hand
  modules/           reusable building blocks, one directory each. Listed under "Modules" below
  policies/          organisation rules, checked against every plan
  environments/
    _shared/         provider, version and variable files, defined once
    dev/
      env.tfvars     the values that make this environment different
      foundation/    state layer: network, keys, identity
      data/          state layer: stores
    staging/
    production/
```

Three ideas hold it together.

1. **Modules contain logic, environments contain values.** A module never configures a provider or mentions an environment by name. An environment layer is a short `main.tf` that calls modules with values.
2. **Environments differ in values, never in structure.** `providers.tf`, `versions.tf` and `variables.tf` in every layer are links to the single copy in `_shared`. Adding a provider or a shared variable is one edit that reaches all three environments.
3. **State is split into layers.** Each layer directory has its own state, so a change is planned and applied against a small part of the environment.

## Commands

All commands take `ENV` (`dev`, `staging`, `production`) and `LAYER`. The defaults are `dev` and `foundation`.

```bash
make up                          # the emulator must be running
make bootstrap                   # once per emulator start: creates the state bucket
make plan                        # dev, foundation
make apply ENV=staging
make destroy ENV=staging
make teardown ENV=staging        # lift deletion protections, then destroy every layer
make validate                    # format check and validate everything
make test                        # module plan tests. Nothing needs to be running
make test-emulator               # module apply tests, against the emulator
make smoke                       # ask the AWS API whether the environment looks right
make state-audit                 # fail if the remote state holds a secret value
make data-check                  # use the stores the way a service would: inventory key design, SQL on the catalog database
make policy                      # plan a layer and check it against the policies
```

By default these target the local emulator. To target real AWS with your own credentials:

```bash
make plan ENV=dev TARGET=aws
```

## One switch between the emulator and AWS

The provider has one input that decides the target, `aws_endpoint_url`:

|                    | Emulator                                          | AWS                           |
| ------------------ | ------------------------------------------------- | ----------------------------- |
| `aws_endpoint_url` | `http://localhost:4566`                           | unset                         |
| Credentials        | The environment's account id as a placeholder key | The standard credential chain |
| Service endpoints  | All pointed at the emulator                       | Real                          |
| Modules            | Identical                                         | Identical                     |

No module contains a condition on the target. If the emulator behaves differently from AWS, the difference is recorded in [emulator differences](../docs/architecture/emulator-differences.md).

## State

Every layer keeps its state in one S3 bucket in the shared-services account, under `<environment>/<layer>/terraform.tfstate`, encrypted with a dedicated KMS key, versioned, and locked with a lock object beside it. `make init` configures this. The design is in [decision record 0009](../docs/adr/0009-remote-state-in-s3-with-native-locking.md), and what to do when state is locked or wrong is in the [state runbook](../docs/runbooks/terraform-state.md).

## Safety

- **Wrong account.** The provider is given `allowed_account_ids` from the environment's `env.tfvars`. Running the production layer with staging credentials stops before anything is planned.
- **Wrong versions.** Terraform and provider versions are pinned, and each layer's lock file is committed with checksums for Linux and macOS.
- **Naming and tags.** Names and tags come from the `context` module and from provider default tags, so a resource cannot be created without them.

## Accounts

| Environment | Directory    | Short name in resource names | Account id     |
| ----------- | ------------ | ---------------------------- | -------------- |
| Development | `dev`        | `dev`                        | `111111111111` |
| Staging     | `staging`    | `stg`                        | `222222222222` |
| Production  | `production` | `prod`                       | `333333333333` |

The account ids are placeholders. Against the emulator they give each environment its own isolated account. For a real deployment, replace them in each `env.tfvars`.

## Adding a layer

1. Create `infra/environments/<env>/<layer>/` in all three environments.
2. Link the shared files:

   ```bash
   ln -s ../../_shared/providers.tf providers.tf
   ln -s ../../_shared/versions.tf versions.tf
   ln -s ../../_shared/variables.tf variables.tf
   ```

   Link `backend.tf` the same way.

3. Write `main.tf` and `outputs.tf`. Call modules, pass values, publish what other layers need to Parameter Store.
4. Copy `.terraform.lock.hcl` from an existing layer, or run `terraform providers lock` for the three platforms.
5. `make validate`, then `make apply LAYER=<layer>` and `make destroy LAYER=<layer>` against the emulator.

## Adding a module

```bash
make module NAME=sqs-consumer-queue
```

This creates a skeleton that meets the [module standards](../docs/architecture/module-standards.md): versions, a `name` and `tags` input, a test file, an example and a README. Add the resources, write the tests, describe the module in its README, then run `make docs` and `make check`.

## Modules

| Module                                                         | Creates                                                                               |
| -------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| [access-roles](modules/access-roles/README.md)                 | The deploy, operator and audit roles, and the GitHub identity provider                |
| [account-baseline](modules/account-baseline/README.md)         | Account-wide safe defaults: no public buckets, encrypted volumes, access analyzer     |
| [context](modules/context/README.md)                           | Nothing. Builds the names and tags every other module uses                            |
| [data-bucket](modules/data-bucket/README.md)                   | A private, encrypted, versioned bucket with lifecycle rules and access policies       |
| [dynamodb-table](modules/dynamodb-table/README.md)             | A table with encryption, point-in-time recovery, indexes, streams and access policies |
| [kms-key](modules/kms-key/README.md)                           | A rotating encryption key with an alias and a key policy that delegates to IAM        |
| [permission-boundary](modules/permission-boundary/README.md)   | The limit on what any workload role in an environment can be granted                  |
| [postgres-database](modules/postgres-database/README.md)       | PostgreSQL on RDS with managed credentials, enforced TLS, backups and logs            |
| [service-config](modules/service-config/README.md)             | A service's parameters and secrets under its own path, with the policy to read them   |
| [state-bucket](modules/state-bucket/README.md)                 | The encrypted, versioned bucket that holds Terraform state                            |
| [tier-security-groups](modules/tier-security-groups/README.md) | One security group per tier, linked by group reference                                |
| [vpc](modules/vpc/README.md)                                   | A three-tier network across three zones, with an isolated data tier                   |
| [vpc-endpoints](modules/vpc-endpoints/README.md)               | Gateway and interface endpoints, so traffic to AWS services stays on the AWS network  |
| [vpc-flow-logs](modules/vpc-flow-logs/README.md)               | A record of VPC traffic in CloudWatch Logs, with a narrow delivery role               |
| [workload-role](modules/workload-role/README.md)               | The role a workload runs as, with trust set by compute type and a required boundary   |
