# Restoring data

How to get data back, for each kind of store. Read the first section before touching anything.

- [Before you restore](#before-you-restore)
- [Which copy to restore from](#which-copy-to-restore-from)
- [A PostgreSQL database](#a-postgresql-database)
- [A DynamoDB table](#a-dynamodb-table)
- [An object in S3](#an-object-in-s3)
- [The stock cache](#the-stock-cache)
- [From the backup vault](#from-the-backup-vault)
- [After a restore](#after-a-restore)
- [What has and has not been tested](#what-has-and-has-not-been-tested)

## Before you restore

1. **Stop the damage first.** If something is still writing bad data, stop it: scale the service to zero or disable the consumer. A restore under a running fault restores into the fault.
2. **Decide the moment.** Find the time just before the damage: the deployment time, the first bad record, the alarm. Write it down in UTC.
3. **Restore beside, never over.** Every procedure below creates a new store next to the damaged one. The damaged one is kept until the restore is verified. It is evidence, and it is the fallback.
4. **Say so.** Open an incident and state what is being restored, to what time, and what will be lost between that time and now.

Restoring needs a role with restore permissions. The operator role and the backup service's role cannot restore, on purpose. An administrator does it.

## Which copy to restore from

| Situation                                           | Use                                    | Granularity    | How far back                                      |
| --------------------------------------------------- | -------------------------------------- | -------------- | ------------------------------------------------- |
| Bad data was written, or data was deleted, recently | The store's own point-in-time recovery | Any second     | Databases: 14 days in production. Tables: 35 days |
| An object was overwritten or deleted                | The previous version in S3             | Each write     | 90 days                                           |
| The store itself is gone, or its own backups are    | The backup vault                       | One copy a day | 35 days                                           |
| The cache is wrong or empty                         | Nothing. It is rebuilt                 |                |                                                   |

Point-in-time recovery is finer and faster. The vault exists for the case where the store and its own backups are lost together, and its copies cannot be deleted by the roles that could delete the original.

## A PostgreSQL database

Restores to a **new instance**. The original is untouched.

```bash
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier meridian-prod-catalog-db \
  --target-db-instance-identifier meridian-prod-catalog-db-restored \
  --restore-time 2031-03-04T09:55:00Z \
  --db-subnet-group-name meridian-prod-catalog-db \
  --vpc-security-group-ids <data security group id> \
  --no-publicly-accessible
```

Use `--use-latest-restorable-time` in place of `--restore-time` to restore to the most recent moment available.

Then:

1. Wait for the instance to be `available`.
2. Connect and check the data at the damaged point. `make data-check` shows how to find the credentials: the restored instance has a new master secret.
3. Choose how to bring it into service:
   - **Copy the missing rows back** into the original, when the damage is limited to known rows or tables. Safest, and the original keeps its identity.
   - **Switch to the restored instance**, when the original is beyond repair. Import it into Terraform as the instance of the `data` layer and remove the old one from state. This is a pull request, reviewed, with the plan read carefully.
4. Delete the restored instance when it is no longer needed, if rows were copied back.

## A DynamoDB table

Restores to a **new table**.

```bash
aws dynamodb restore-table-to-point-in-time \
  --source-table-name meridian-prod-inventory-movements \
  --target-table-name meridian-prod-inventory-movements-restored \
  --restore-date-time 2031-03-04T09:55:00Z
```

A restored table does not inherit everything. Set these again, or let Terraform do it after importing the table: point-in-time recovery, the stream, time to live, tags, autoscaling, and deletion protection.

For the two inventory tables there is a better option than restoring both:

- **The movement ledger** is the source of truth. Restore it if it is damaged.
- **Stock levels** are derived. If only levels are wrong, do not restore them. Rebuild them by replaying the ledger, which is what [rule INV-6](../domain/domain-model.md#inventory) makes possible.

## An object in S3

Buckets are versioned. Nothing is restored: the earlier version is still there.

```bash
# List the versions of an object.
aws s3api list-object-versions --bucket <bucket> --prefix suppliers/acme/2031-03-04.csv

# A deleted object: remove the delete marker and the previous version is current again.
aws s3api delete-object --bucket <bucket> --key suppliers/acme/2031-03-04.csv --version-id <delete marker id>

# An overwritten object: copy the wanted version over the current one.
aws s3api copy-object --bucket <bucket> --key suppliers/acme/2031-03-04.csv \
  --copy-source "<bucket>/suppliers/acme/2031-03-04.csv?versionId=<wanted version id>"
```

Removing a delete marker needs `s3:DeleteObjectVersion`, which workload roles are denied. An administrator does it.

## The stock cache

Do not restore it. Flush nothing and repair nothing. Restart the consumers that fill it, or let it fill on demand. Until it is warm, reads fall through to the stock level table, which is slower and correct.

## From the backup vault

When the store and its own backups are gone.

```bash
# Find the recovery point.
aws backup list-recovery-points-by-backup-vault --backup-vault-name meridian-prod-backup \
  --by-resource-arn <arn of the lost store>

# See what a restore needs for this kind of resource.
aws backup get-recovery-point-restore-metadata --backup-vault-name meridian-prod-backup \
  --recovery-point-arn <recovery point arn>

# Restore. The metadata is the output of the previous command, edited to name the new store.
aws backup start-restore-job --recovery-point-arn <recovery point arn> \
  --iam-role-arn <restore role arn> --metadata file://restore-metadata.json
```

The restore role is not the backup service's role, which can only take backups. It is created by an administrator when a restore is needed, with `AWSBackupServiceRolePolicyForRestores`, and removed afterwards.

## After a restore

- Run `make smoke` and `make data-check` for the environment.
- Reconcile Terraform. `make plan` for the `data` layer must be read line by line before anything is applied: the state still describes the old store.
- Record in the incident what was restored, to what time, what was lost, and how long it took. That duration is the measured recovery time, and it goes into the [data architecture](../architecture/data.md#retention-and-recovery) in place of the target.
- Keep the damaged store until the incident review is done.

## What has and has not been tested

|                                                                               | Tested               | How                                                             |
| ----------------------------------------------------------------------------- | -------------------- | --------------------------------------------------------------- |
| The backup plan selects the right stores by tag                               | Yes                  | `make data-check`, in the pipeline                              |
| A backup of the ledger completes and lands in the vault                       | Yes, on the emulator | `make data-check`                                               |
| The restore commands for RDS and DynamoDB are accepted and create a new store | Yes, on the emulator | Run by hand while writing this                                  |
| The restored store contains the data                                          | **No**               | The emulator creates the new store empty. It does not copy data |
| Restore times                                                                 | **No**               | They can only be measured on AWS                                |
| Restoring from the vault                                                      | **No**               |                                                                 |

A restore procedure that has never restored real data is a draft. A restore drill on a real account, with timings, is part of milestone 11, and this runbook is to be corrected by it.
