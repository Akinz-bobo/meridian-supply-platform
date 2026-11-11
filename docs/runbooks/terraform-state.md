# Runbook: Terraform state

What to do when state is locked, wrong or missing. Each procedure here was rehearsed against the emulator before it was written down. The design is in [decision record 0009](../adr/0009-remote-state-in-s3-with-native-locking.md).

| Symptom                                                                  | Go to                                                                           |
| ------------------------------------------------------------------------ | ------------------------------------------------------------------------------- |
| `Error acquiring the state lock`                                         | [State is locked](#state-is-locked)                                             |
| A bad apply needs undoing, or `plan` wants to recreate things that exist | [Roll state back to an earlier version](#roll-state-back-to-an-earlier-version) |
| A resource was changed or deleted by hand                                | [State and reality disagree](#state-and-reality-disagree)                       |
| The bootstrap stack's local state is gone                                | [The bootstrap state is lost](#the-bootstrap-state-is-lost)                     |

## Before you touch state

1. **Stop the pipeline** for the affected environment, so nothing applies while you work.
2. **Say what you are doing** where the team will see it. Two people repairing state at once is how a small problem becomes a large one.
3. **Know which state.** Every command below acts on one environment and one layer. Check both.

Where things are:

|              |                                                                             |
| ------------ | --------------------------------------------------------------------------- |
| Bucket       | `meridian-shared-tfstate-<account>-<region>` in the shared-services account |
| State object | `<environment>/<layer>/terraform.tfstate`                                   |
| Lock object  | `<environment>/<layer>/terraform.tfstate.tflock`                            |

The examples use `dev` and `foundation`. Set these first:

```bash
BUCKET=meridian-shared-tfstate-444444444444-eu-west-1
KEY=dev/foundation/terraform.tfstate
DIR=infra/environments/dev/foundation
make init ENV=dev LAYER=foundation
```

## State is locked

```
Error: Error acquiring the state lock
Lock Info:
  ID:        11111111-2222-3333-4444-555555555555
  Path:      meridian-shared-tfstate-.../dev/foundation/terraform.tfstate
  Operation: OperationTypeApply
  Who:       ci@runner
  Created:   2026-11-11 10:00:00 +0000 UTC
```

A lock means someone is applying, or someone was and their process died.

1. **Read `Who` and `Created`.** If it is recent, it is probably a real apply. Wait, or ask that person.
2. **Check the pipeline** for a run in progress against this environment.
3. Only when you are sure nothing is running, remove the lock using the `ID` from the error:

   ```bash
   terraform -chdir=$DIR force-unlock 11111111-2222-3333-4444-555555555555
   ```

4. Run `make plan` and read it. A process that died mid-apply may have created resources that state does not know about. If the plan wants to create something that already exists, go to [State and reality disagree](#state-and-reality-disagree).

Never remove a lock to get past someone else's apply. Two applies against one state corrupt it.

## Roll state back to an earlier version

The bucket keeps every version of every state file for 90 days.

Use this when state itself is wrong: a failed migration, a mistaken `state rm`, a corrupted write. It does not undo changes to real resources. If the resources changed too, restoring old state will make Terraform want to change them back, which may or may not be what you want. Read the plan.

1. List the versions, newest first:

   ```bash
   aws s3api list-object-versions --bucket $BUCKET --prefix $KEY \
     --query 'Versions[].[VersionId,LastModified,IsLatest]' --output table
   ```

2. Download the version you want and look at it before using it:

   ```bash
   aws s3api get-object --bucket $BUCKET --key $KEY --version-id <version-id> restore.tfstate
   jq '{serial, lineage, resources: (.resources | length)}' restore.tfstate
   ```

3. Terraform refuses to replace state with one that has a lower serial number. Raise the serial above the current one:

   ```bash
   CURRENT=$(terraform -chdir=$DIR state pull | jq .serial)
   jq ".serial = $((CURRENT + 1))" restore.tfstate > restore-bumped.tfstate
   ```

4. Push it. This takes the lock, so it cannot race an apply:

   ```bash
   terraform -chdir=$DIR state push "$PWD/restore-bumped.tfstate"
   ```

5. Run `make plan` and read every line. The plan is now the difference between the restored state and reality.
6. Delete the downloaded files. They are a copy of state and may contain secrets.

The restore is itself a new version, so it can be undone the same way.

## State and reality disagree

Someone changed a resource in the console, or an apply died halfway.

| What the plan shows                                | Meaning                                   | Fix                                                                                 |
| -------------------------------------------------- | ----------------------------------------- | ----------------------------------------------------------------------------------- |
| Wants to **change** an attribute you did not touch | The resource was edited outside Terraform | Apply, to put it back. If the manual change was right, change the code first        |
| Wants to **create** something that exists          | It exists but is not in state             | `terraform import <address> <id>`, then plan again                                  |
| Wants to **destroy** something still needed        | It is in state but no longer in the code  | Restore the code, or if it should be kept unmanaged, `terraform state rm <address>` |
| Errors reading a resource that was deleted by hand | It is in state but gone                   | `terraform apply -refresh-only` to accept that it is gone, then plan again          |

Prefer `import` and `-refresh-only` over editing state by hand. Never edit the state file in a text editor.

## The bootstrap state is lost

`infra/bootstrap` is the one stack whose state is local, because it creates the bucket remote state lives in. If that file is lost, nothing is broken: the bucket and key still exist and every environment still works. Only the ability to change the bucket through Terraform is affected.

To rebuild it, import the existing resources:

```bash
cd infra/bootstrap
terraform init
terraform import -var-file=bootstrap.tfvars module.state_bucket.aws_s3_bucket.state $BUCKET
terraform import -var-file=bootstrap.tfvars module.state_bucket.aws_kms_alias.state alias/$BUCKET
terraform import -var-file=bootstrap.tfvars module.state_bucket.aws_kms_key.state <key-id>
terraform plan -var-file=bootstrap.tfvars
```

Import the remaining bucket settings the plan lists as "to create" in the same way, until the plan is empty.

To avoid needing this, after the first apply on a real account copy the bootstrap state into the bucket it created, under `shared/bootstrap/terraform.tfstate`, by adding the same backend block the layers use and running `terraform init -migrate-state`. Against the emulator this is skipped, because the emulator is rebuilt from nothing on every start.

## What was rehearsed, and what was not

| Procedure                                                                 | Rehearsed against the emulator                    |
| ------------------------------------------------------------------------- | ------------------------------------------------- |
| Two applies at once: the second is refused                                | Yes                                               |
| Stale lock: plan fails, `force-unlock`, plan succeeds                     | Yes                                               |
| Roll back: restore an earlier version with a raised serial, plan is clean | Yes                                               |
| Rebuild bootstrap state by import                                         | No. Written from Terraform's documented behaviour |
| Migrate bootstrap state into the bucket                                   | No                                                |
