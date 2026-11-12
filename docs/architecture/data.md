# Data architecture

Which store holds what, how sensitive it is, how long it is kept and how it is recovered. The stores are built by the `data` layer of each environment.

- [Stores](#stores)
- [One store per service](#one-store-per-service)
- [Classification](#classification)
- [Retention and recovery](#retention-and-recovery)
- [Differences between environments](#differences-between-environments)
- [The data layer](#the-data-layer)
- [Database credentials](#database-credentials)
- [How it is enforced](#how-it-is-enforced)

## Stores

```mermaid
flowchart LR
    subgraph services[Services]
        catalog[Catalog]
        curation[Curation workflow]
        inventory[Inventory]
        procurement[Procurement]
        budget[Budget]
        planning[Planning]
        gateway[ERP gateway]
        analytics[Analytics]
    end

    subgraph relational[RDS PostgreSQL]
        pgcat[(catalog)]
        pgpro[(procurement)]
        pgbud[(budget)]
    end
    subgraph keyvalue[DynamoDB]
        movements[(movement ledger)]
        levels[(stock levels)]
    end
    subgraph cache[ElastiCache]
        stockcache[(stock read cache)]
    end
    subgraph objects[S3]
        uploads[(supplier uploads)]
        exchange[(file exchange)]
        lake[(data lake)]
    end

    catalog --> pgcat
    curation --> uploads
    inventory --> movements
    inventory --> levels
    inventory --> stockcache
    procurement --> pgpro
    budget --> pgbud
    gateway --> exchange
    analytics --> lake
    planning --> lake
```

| Store                           | Technology     | Module              | Owner       | Why this technology                                                                                                          |
| ------------------------------- | -------------- | ------------------- | ----------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Product master, suppliers       | RDS PostgreSQL | `postgres-database` | Catalog     | Relational, with constraints between products, suppliers and units                                                           |
| Purchase orders, goods receipts | RDS PostgreSQL | `postgres-database` | Procurement | Transactions across order lines                                                                                              |
| Budgets, commitments, approvals | RDS PostgreSQL | `postgres-database` | Budget      | Strong consistency on money                                                                                                  |
| Movement ledger                 | DynamoDB       | `dynamodb-table`    | Inventory   | Append-only, very high write volume, read by batch and by warehouse. See the [inventory data model](inventory-data-model.md) |
| Stock levels                    | DynamoDB       | `dynamodb-table`    | Inventory   | Conditional writes enforce that stock never goes negative                                                                    |
| Stock read cache                | ElastiCache    | `redis-cache`       | Inventory   | Read far more often than it changes. Can be rebuilt from the tables                                                          |
| Supplier uploads                | S3             | `data-bucket`       | Curation    | Files, kept as received                                                                                                      |
| File exchange                   | S3             | `data-bucket`       | ERP gateway | Files to and from the finance system                                                                                         |
| Data lake                       | S3             | `data-bucket`       | Analytics   | Every event, kept cheaply, queried with Athena                                                                               |

The modules are added one at a time in this milestone. A store that belongs to a service is created in the `data` layer, with the service's name as its component, when that service is first needed. Keeping every store in this layer means a change to a service's compute can never produce a plan that touches its data. The supplier uploads bucket is the first.

## One store per service

A store has exactly one owner, and only the owner reads or writes it. Another service that needs the data calls the owner's API or consumes its events ([decision record 0006](../adr/0006-event-backbone-and-messaging-conventions.md)).

This is why catalog, procurement and budget each have a database of their own and not a shared one. A shared database couples services through its schema: one team's migration breaks another team's query, and nobody can say who is allowed to change a table.

The cost is that there are no joins across services. Reports that need them are built from events in the data lake, never by querying the operational databases.

## Classification

Every store carries a `DataClassification` tag. It says how bad it would be if the contents were disclosed, and it decides access, retention and backup.

| Level          | Meaning                                             | Examples here                                             | Consequences                                                           |
| -------------- | --------------------------------------------------- | --------------------------------------------------------- | ---------------------------------------------------------------------- |
| `public`       | Meant to be published                               | The dashboard's static files                              | No restriction on reading. Still encrypted and versioned               |
| `internal`     | For staff. Disclosure is embarrassing, not damaging | Stock levels, movements, the stock cache                  | Read by the owning service and by operators through its API            |
| `confidential` | Disclosure harms the business or a partner          | Supplier prices, purchase orders, budgets, supplier files | Read by the owning service only. Backed up. Access is logged           |
| `restricted`   | Disclosure has legal consequences                   | None at present. Personal data would be                   | As confidential, plus a key and a review of its own before it is added |

The platform holds business data about products, stock and money. It holds almost no personal data: the names and work contact details of supplier contacts and of users. If that changes, the new data is classified `restricted` and gets its own decision record.

## Retention and recovery

RPO is how much recent data may be lost in a recovery. RTO is how long the recovery may take. These are the targets the configuration is built to meet. They have not been measured, because the emulator cannot measure them.

| Store                                     | Classification | Kept for                                 | Protection                                                                                                                                                        | RPO target     | RTO target |
| ----------------------------------------- | -------------- | ---------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------- | ---------- |
| Catalog, procurement and budget databases | `confidential` | As long as the business needs            | Automated backups with point-in-time recovery for 14 days, a standby in a second zone, a final snapshot on deletion, a daily copy in the backup vault for 35 days | 5 minutes      | 1 hour     |
| Movement ledger                           | `internal`     | 7 years. It is the audit record of stock | Point-in-time recovery for 35 days, a daily copy in the backup vault                                                                                              | 5 minutes      | 1 hour     |
| Stock levels                              | `internal`     | Current state only                       | Point-in-time recovery for 35 days. Can also be rebuilt by replaying the ledger                                                                                   | 5 minutes      | 1 hour     |
| Stock read cache                          | `internal`     | Hours                                    | None needed. Rebuilt from the tables                                                                                                                              | Not applicable | 15 minutes |
| Supplier uploads                          | `confidential` | 1 year, then deleted                     | Versioning. Old versions kept 90 days                                                                                                                             | None lost      | Minutes    |
| File exchange                             | `confidential` | 1 year, then deleted                     | Versioning                                                                                                                                                        | None lost      | Minutes    |
| Data lake                                 | `confidential` | 7 years, in colder storage after 90 days | Versioning. Can be rebuilt from the source events for as long as those are retained                                                                               | None lost      | Minutes    |

## Differences between environments

Structure is identical. Sizes and redundancy differ, as values in each environment's `env.tfvars`.

|                                   | dev                                | staging   | production |
| --------------------------------- | ---------------------------------- | --------- | ---------- |
| Database standby in a second zone | No                                 | Yes       | Yes        |
| Database backup retention         | 1 day                              | 7 days    | 14 days    |
| Deletion protection               | Off, the environment is disposable | On        | On         |
| Cache replicas                    | None                               | One       | Two        |
| DynamoDB capacity                 | On demand                          | On demand | On demand  |

## The data layer

```mermaid
flowchart LR
    subgraph foundation[foundation layer]
        net[Network]
        keys[Keys]
        iam[Boundary]
    end
    ps[(Parameter Store<br/>/meridian/env/network/*<br/>/meridian/env/security/*)]
    subgraph data[data layer]
        stores[Stores]
    end
    ps2[(Parameter Store<br/>/meridian/env/data/*)]
    services[Service layers]

    net --> ps
    keys --> ps
    iam --> ps
    ps -- read --> stores
    stores --> ps2
    ps2 -- read --> services
```

The `data` layer is applied after `foundation` and destroyed before it. It reads the subnets, the data security group, the keys and the boundary from Parameter Store, and publishes each store's name, ARN and endpoint the same way. It reads no other layer's state file, so a consumer needs access to a parameter path and not to a state file ([decision record 0008](../adr/0008-layered-state-per-environment.md)).

A missing parameter fails the plan with the parameter's name, which is the signal that the foundation layer has not been applied.

## Database credentials

No database password exists in the repository, in Terraform state or in a plan.

| Credential                                | Created by                            | Stored                                                                             | Used by                                                            |
| ----------------------------------------- | ------------------------------------- | ---------------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| Master user                               | RDS, when the instance is created     | Secrets Manager, under the secrets key, rotated by RDS                             | Administration, and creating application roles. Never by a service |
| Application role, with IAM authentication | A migration run by the owning service | Nowhere. The service asks RDS for a token valid for 15 minutes, using its IAM role | The service                                                        |

A service is allowed to connect by an IAM statement on `arn:aws:rds-db:<region>:<account>:dbuser:<resource id>/<role>`, where the resource id is published by the data layer. So access to a database is granted, reviewed and revoked in the same place as every other permission, and a leaked configuration file contains nothing that opens the database.

`make data-check` connects with the master secret the way an administrator would: it finds the address and the secret in Parameter Store, reads the secret, and runs SQL. Application roles are created with the first service that needs one.

## How it is enforced

| Rule                                                                             | Where                                                                                                                                                                         |
| -------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Every data store carries a `DataClassification` from the scheme                  | Policy `POL-TAG-4`                                                                                                                                                            |
| A data store is not deleted or replaced outside dev without a recorded exception | Policy `POL-PROTECT-1`                                                                                                                                                        |
| Stores are encrypted with the data key                                           | Each module, with tests, and the scanner                                                                                                                                      |
| Stores are in the data subnets with the data security group                      | Each module's inputs, and the smoke test                                                                                                                                      |
| Databases are private, encrypted, backed up, protected, and given no password    | The `postgres-database` module, and policies `POL-DB-1` to `POL-DB-5` for a database created any other way                                                                    |
| A database can be reached and behaves as PostgreSQL                              | `make data-check`, in the pipeline after each apply                                                                                                                           |
| Layers are applied and destroyed in order                                        | `scripts/layers.sh`, used by `make apply-all` and `make destroy-all`                                                                                                          |
| A protected store cannot be destroyed by accident                                | Deletion protection follows `disposable`, which only dev sets. `make destroy-all` fails in staging and production, and `make teardown` is the deliberate two-step alternative |
