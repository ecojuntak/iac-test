# Terraform stacks (per-component roots)

Per-component root modules, shared across all teams and environments. A cell of the deployment matrix is `(team, environment, component)`:

```
terraform -chdir=stack/<component> plan \
  -var="team=<name>" -var="environment=<env>" \
  -backend-config="bucket=<state-bucket>" \
  -backend-config="key=<team>/<environment>/<component>.tfstate" \
  -backend-config="region=ap-southeast-1" \
  -backend-config="dynamodb_table=<table>"
```

## Team layout

Each team declares resources per environment, one file per env:

```
teams/
  commerce/
    dev.yaml
    staging.yaml
    prod.yaml
```

All env files share `schema/schema.json`. Path-based change detection maps `teams/commerce/prod.yaml` directly to the `(commerce, prod, *)` cells, so changing one env never plans the others.

A team file declares its buckets (name + visibility, no defaults) and its role — exactly one, mandatory. The contract is **implicit access**: the role automatically gets access to every bucket declared in the same file — bucket names exist exactly once, so there is no re-declaration to typo or drift out of sync, and no per-role bucket selection to review:

```yaml
s3:
  role:
    name: app
  buckets:
    - name: user-service
      scope: private
    - name: product-service
      scope: public
```

## Layout

| Root | Reads | State key |
|------|-------|-----------|
| `stack/s3` | `teams/<name>/<environment>.yaml` `s3.buckets` | `<team>/<environment>/s3.tfstate` |
| `stack/iam` | `teams/<name>/<environment>.yaml` `s3.role` + bucket names | `<team>/<environment>/iam.tfstate` |

Roots are decoupled: `stack/iam` passes declared bucket names to `module/access/s3`, which composes policy ARNs using the well-known S3 ARN format (`arn:aws:s3:::<bucket>`), so no `terraform_remote_state` wiring is needed. Components that need outputs from another component can opt into `terraform_remote_state` later.

## Naming convention

| Resource | Pattern | Example |
|----------|---------|---------|
| Bucket   | `<environment>-<name>` | `dev-user-service` |
| IAM role | `<team>-<environment>-<name>` | `commerce-prod-app` |

The asymmetry is deliberate:

- **Buckets are named after the service**, not the team. Ownership of a bucket/service can transfer between teams; without the team in the name, a transfer is a config + state change — never a rename with data migration. Because team is absent, two teams claiming the same name in one environment cannot be caught structurally (each team's state is isolated); `scripts/validate_team_configs.py` catches that at PR time with the repo-wide view.
- **Roles are named after the grantee.** A role *is* the team's access identity, so it must carry the team; the full prefix also keeps account-global IAM names unique across cells.

Both conventions are **enforced by the platform, not by convention documents**: `module/s3` composes `<environment>-<name>` itself (a team cannot produce an out-of-convention bucket name), and `module/iam` composes `<team>-<environment>-<name>` (a check block guards IAM's 64-character limit). Teams only ever declare logical names.

Composed names use the full environment name (not letters like `d`/`s`/`p`), so no env→letter mapping exists. `module/s3` validates `environment` against a fixed enum (`dev`, `staging`, `prod`) — adding a new environment is a one-line enum change in the module plus the new YAML file, keeping the accepted set explicit and reviewable.

## Adding a team

1. `teams/<name>/` with `<env>.yaml` files (schema in `schema/schema.json`), e.g. `teams/payments/`
2. CI picks them up automatically: change detection, plans, applies, and tests all key off `teams/**` globs

## Composition: identity vs. access

`stack/iam` splits responsibilities in three:

- **Identity** — `module/iam` composes the role name (`<team>-<environment>-<name>`, guarded by a 64-character check) and attaches policy documents. It has zero knowledge of S3 (or any service).
- **Access rendering** — `module/access/<service>` owns each service's access preset and renders the policy JSON. The S3 preset (`module/access/s3`) is a fixed object-level action set (`GetObject`, `GetObjectVersion`, `ListBucket`, `PutObject`, `DeleteObject`) scoped to ARNs it composes as `<environment>-<name>` from the declared bucket names `stack/iam` passes in. Bucket-level configuration actions are excluded: bucket guardrails are platform-owned, and the requirement is binary (a role reaches its team's buckets or it doesn't), so there is no per-team level selector.
- **Aggregation** — `stack/iam` reads the team's declared access and feeds it to each service's access module; one rendered document per service is attached to the role.

The single role in a cell gets one rendered policy document per service, attached as inline policies (S3's is named `s3-access`). Because the bucket list derives from the same declaration list the bucket stack consumes, the role can never reference a bucket the team doesn't own — the "own buckets only" guarantee holds by construction, with no validation layer to bypass or maintain.

## Adding a component (e.g. RDS)

1. `module/rds/` — reusable resource module
2. `module/access/rds/` — the RDS access preset + policy renderer (the service owns what "RDS access" means, same as S3)
3. `stack/rds/` — root reading `teams/<name>/<environment>.yaml`, backend key `<team>/<environment>/rds.tfstate`
4. `stack/iam/main.tf` — one `module "rds_access"` block feeding it the declared access, plus one entry in the role's `policy_documents` map

Neither `module/iam` nor the role-per-team layout changes: the team's single role accumulates policies from every service, which is exactly what "one IAM role per team" requires. CI picks up the new component automatically: `stack/rds/**` changes run rds for all teams × envs; `teams/<team>/<env>.yaml` changes run every component for that team × env.

Keep secrets out of state: prefer RDS `manage_master_user_password = true` or Secrets Manager values created outside Terraform.

## Environments and accounts

Environments may live in different AWS accounts. Resolution order (first hit wins) for the per-cell job:

- **OIDC role** (secret): `AWS_ROLE_TO_ASSUME_<TEAM>_<ENV>` → `AWS_ROLE_TO_ASSUME_<ENV>` → `AWS_ROLE_TO_ASSUME`
- **Region** (variable): `AWS_REGION_<ENV>` → `AWS_REGION`
- **State bucket/table** (variables): `TF_STATE_BUCKET_<ENV>` / `TF_STATE_TABLE_<ENV>` → `TF_STATE_BUCKET` / `TF_STATE_TABLE`

Each account needs an OIDC provider trusting the repo plus a role whose trust policy allows the workflow. State keys include the environment, so even a single shared state backend keeps envs isolated; per-env state buckets are recommended when envs are separate accounts.

Protected envs (currently `prod`) deploy through a matching GitHub Environment — configure required reviewers there to gate applies.

## State isolation

One state file per `(team, environment, component)` in the state bucket. For hardening options (per-team/per-env buckets, IAM prefix scoping) see the CI section below — restrict each assumed role to its own `<team>/<environment>/*` prefix.

## CI

`.github/workflows/terraform.yaml`:

- **PR**: `terraform plan` for every affected `(team, environment, component)` cell; plans posted as PR comments (one per cell, marker-upserted). Job fails if any plan fails.
- **Push to `main`**: same matrix, `terraform plan` + `apply -auto-approve` (gated by GitHub Environment for protected envs).
- **Config validation**: `scripts/validate_team_configs.py` runs first on every PR/push — JSON-schema validation of every team file, plus the cross-team bucket name uniqueness gate (see Naming convention).
- **Module tests**: `terraform test` runs on every PR/push — `module/iam` and `module/s3` (`mock_provider "aws"`) for their contracts (composed role naming, policy attachment; composed bucket naming, scope guardrails) and `module/access/s3` (providerless) for the access preset and ARN composition — so behavior is validated without deploying to a real AWS account.

Change detection matrix:

| Changed | Cells affected |
|---------|----------------|
| `teams/commerce/prod.yaml` | all components × team commerce × prod |
| `stack/<c>/**` | component c × all teams × all envs |
| `module/**`, `schema/**`, workflow file | all teams × all envs × all components |

### Deletions

| Deleted | Workflow behavior |
|---------|-------------------|
| A bucket entry in `teams/<team>/<env>.yaml` | Normal path: plan shows the bucket's destroy (implicit access shrinks the IAM policy too). Applies fail on non-empty buckets — `module/s3` deliberately has no `force_destroy`; empty it first. |
| `teams/<team>/<env>.yaml` (whole file) | Dedicated `destroy` job: checks out the commit **before** the deletion, runs `terraform plan -destroy` (PR preview) or `terraform destroy -auto-approve` (merge), per component. State is left clean; no orphaned resources, no red plan on a missing file. |
| Whole `teams/<team>/` directory | Same as above for every env file the directory contained — one destroy cell per `(env, component)`. |

Destroy safety:

- The job refuses to run if the file exists in the checked-out (pre-change) commit — that means the change wasn't a deletion (delete/re-add race across PRs), and destroying would act on stale assumptions.
- PRs only preview (`terraform plan -destroy`); destruction runs on merge to `main`, gated by the same GitHub Environment mechanism as applies (required reviewers on prod).

Required repo variables/secrets:

| Name | Kind | Purpose |
|------|------|---------|
| `AWS_REGION` | variable | Default provider region (per-env override: `AWS_REGION_<ENV>`) |
| `TF_STATE_BUCKET` | variable | Default state bucket (per-env override: `TF_STATE_BUCKET_<ENV>`) |
| `TF_STATE_TABLE` | variable | Default lock table (per-env override: `TF_STATE_TABLE_<ENV>`) |
| `AWS_ROLE_TO_ASSUME` | secret | Default OIDC role ARN |
| `AWS_ROLE_TO_ASSUME_<ENV>` | secret | Per-env role override |
| `AWS_ROLE_TO_ASSUME_<TEAM>_<ENV>` | secret | Per-team-per-env role override |

## Migrating from pre-convention bucket names

`module/s3` now composes `<environment>-<name>` (previously the raw logical name). Module instance keys stay logical, so **state addresses are unchanged** — only the `bucket` attribute changes, which forces a bucket *replacement* (destroy + recreate). If a cell was already applied with raw names, either let Terraform replace (fine for empty buckets; data must be migrated out first) or `state mv` the old physical bucket into the new address. If nothing was applied yet, ignore this section.

## Migrating from the previous principal module

`module/iam` was refactored from a "principal + S3 access" module (`type`/`s3_buckets`/`s3_level`/`bucket_arns`) into a pure role module (`name`, `assume_role_policy`, `policy_documents`). Resource addresses changed:

- `aws_iam_role.this[0]` → `aws_iam_role.this`
- `aws_iam_user.this[0]` → removed (users dropped)
- `aws_iam_role_policy.s3_access[0]` → `aws_iam_role_policy.this["s3-access"]`

If a cell was already applied with the old module, realign state before the next apply:

```
terraform -chdir=stack/iam state mv 'aws_iam_role.this[0]' 'aws_iam_role.this'   # per affected cell
terraform -chdir=stack/iam state mv 'aws_iam_role_policy.s3_access[0]' 'aws_iam_role_policy.this["s3-access"]'
terraform -chdir=stack/iam state rm 'aws_iam_user_policy.s3_access[0]'           # if users were used
terraform -chdir=stack/iam state rm 'aws_iam_user.this[0]'
```

If nothing was applied yet, ignore this section.

## Migrating from the old single root

If the previous `stack/main.tf` (state key `stack/team-<team>.tfstate`) was already applied, move state per component:

```
terraform -chdir=stack/s3 init -backend-config="key=<team>/<environment>/s3.tfstate" ... && \
terraform -chdir=stack/s3 state push team-<team>.tfstate   # pulled from old state
```

or, from the old root, `terraform state mv` into per-component states via `terraform state push`. If nothing was applied yet, ignore this section.

## Migrating from team-<name>/ directories

Team configs moved from `team-<name>/` to `teams/<name>/` (no `team-` prefix), and state keys from `team-<team>/...` to `<team>/...`. Nothing else changed — bucket names are team-agnostic, so no resource renames. If state exists under old keys, move it in the state bucket:

```
aws s3 mv s3://<state-bucket>/team-<team>/<environment>/<component>.tfstate \
           s3://<state-bucket>/<team>/<environment>/<component>.tfstate
```

If nothing was applied yet, ignore this section.