# Infrastructure

Everything the platform runs on, as Terraform. The reasoning behind the layout is in decision records [0003](../docs/adr/0003-terraform-for-infrastructure.md), [0007](../docs/adr/0007-environments-and-account-isolation.md) and [0008](../docs/adr/0008-layered-state-per-environment.md).

## Layout

```
infra/
  modules/           reusable building blocks
    context/         naming and tagging, used by every other module
  environments/
    _shared/         provider, version and variable files, defined once
    dev/
      env.tfvars     the values that make this environment different
      foundation/    one state layer
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
make plan                        # dev, foundation
make apply ENV=staging
make destroy ENV=staging
make validate                    # format check and validate everything
make test                        # module tests
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

3. Write `main.tf` and `outputs.tf`. Call modules, pass values, publish what other layers need to Parameter Store.
4. Copy `.terraform.lock.hcl` from an existing layer, or run `terraform providers lock` for the three platforms.
5. `make validate`, then `make apply LAYER=<layer>` and `make destroy LAYER=<layer>` against the emulator.

## Adding a module

Module standards (inputs, outputs, tests, generated documentation) are being defined in [#15](https://github.com/Akinz-bobo/meridian-supply-platform/issues/15). Until then, follow `modules/context`.
