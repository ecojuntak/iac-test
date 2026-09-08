# Contributing — platform team guide

This repo is operated by the platform team; product teams never edit Terraform (their guide lives in the [README](README.md)). If you are changing `stack/`, `module/`, `schema/`, or the workflow, this is your doc.

## Repository layout

| Path | Role |
|------|------|
| `teams/<team>/<env>.yaml` | Declarative input. The only thing teams edit. Isolated per cell `(team, environment)`. |
| `schema/schema.json` | Contract for team configs. Validated by CI and by editors live. |
| `stack/s3` | Root: buckets for a cell. State: `<team>/<environment>/s3.tfstate`. |
| `stack/iam` | Root: the cell's role + rendered policies. State: `<team>/<environment>/iam.tfstate`. |
| `module/s3` | One bucket with scope guardrails. Composes `<environment>-<name>` itself. |
| `module/iam` | One role + attached policy documents. Zero service knowledge. |
| `module/access/<service>` | One service's access preset + policy renderer (currently `s3`). |
| `scripts/validate_team_configs.py` | Repo-wide gates isolated states cannot see: schema conformance + cross-team bucket uniqueness. |

Detailed per-module contracts: `module/s3/README.md`, `module/iam/README.md`, `module/access/s3/README.md`, and the composition deep-dive in `stack/README.md`.

## The composition model

Three responsibilities, deliberately separated:

1. **Access** — `module/access/<service>` owns what "S3 access" (later: RDS, …) means: the action preset and the rendered policy JSON, given declared resource names. Each service owns its own preset.
2. **Identity** — `module/iam` composes `<team>-<environment>-<role_name>`, guards the 64-char IAM limit, attaches policy documents. It never learns about any service.
3. **Aggregation** — `stack/iam` reads the team's declared access and wires (1) into (2). Adding a service = new `module/access/<service>` + one `policy_documents` entry; nothing else changes.

Roots stay decoupled by construction: `stack/iam` passes logical bucket names to `module/access/s3`, which composes ARNs from the well-known S3 format — no `terraform_remote_state` between roots. Opt into it only when a component truly needs another's outputs.

## Running things locally

```bash
# Validate all team configs (what CI runs first)
python3 scripts/validate_team_configs.py

# Module tests (mocked AWS; no account needed)
terraform -chdir=module/s3 init -backend=false -input=false && terraform -chdir=module/s3 test
terraform -chdir=module/access/s3 init -backend=false -input=false && terraform -chdir=module/access/s3 test
terraform -chdir=module/iam init -backend=false -input=false && terraform -chdir=module/iam test

# Plan one cell locally (needs AWS credentials + state backend access)
terraform -chdir=stack/s3 init \
  -backend-config="bucket=<state-bucket>" \
  -backend-config="key=<team>/<environment>/s3.tfstate" \
  -backend-config="region=ap-southeast-1" \
  -backend-config="dynamodb_table=<table>"
terraform -chdir=stack/s3 plan -var="team=<team>" -var="environment=<env>"
```

## CI behavior (`.github/workflows/terraform.yaml`)

- **PR**: config validation → module tests → `terraform plan` for every affected `(team, environment, component)` cell, posted as one upserted comment per cell.
- **Push to `main`**: same matrix plus `terraform apply -auto-approve`. Protected environments (`prod`) are gated by GitHub Environment required reviewers.
- **Deletions**: deleting a `teams/<team>/<env>.yaml` emits cells into a separate `destroy_matrix`; the `destroy` job checks out the pre-change commit, previews the destroy on PRs, and destroys on merge. It refuses to run if the file exists at the checked-out commit (delete/re-add race). Deleted `stack/` directories are not handled — remove resources before deleting a stack.
- **Change detection**: `module/**`, `schema/**`, or workflow changes → full matrix; `stack/<c>/**` → component c everywhere; `teams/<team>/<env>.yaml` → every component of that cell.

Required repo variables/secrets: `TF_STATE_BUCKET`, `TF_STATE_TABLE`, `AWS_REGION` (variables), each with optional per-environment overrides (`TF_STATE_BUCKET_<ENV>`, …), and `AWS_ROLE_TO_ASSUME` (secret) with `<ENV>` / `<TEAM>_<ENV>` overrides. Full tables in `stack/README.md`.

## Guardrails — keep them structural

The repo's core rule: **anything a team must not bypass is enforced by construction, not by review.** Bucket names are composed by `module/s3`; role names by `module/iam`; access is implicit from the declaration; bucket-level actions never appear in the preset. When extending:

- **New service (e.g. RDS)**: `module/rds` (resources) + `module/access/rds` (preset/renderer) + `stack/rds` (root) + one entry in `stack/iam`'s `policy_documents`. Follow `module/access/s3` as the template — providerless, preset + renderer only.
- **New environment**: add to the enums in `module/s3`, both stacks, and the workflow's destroy-cell env list, plus the team YAML files.
- **New team**: nothing outside `teams/<name>/`. CI picks it up automatically.
- **Secrets**: keep them out of state — use RDS `manage_master_user_password` or Secrets Manager values created outside Terraform.

## State model

One state file per `(team, environment, component)` — see the state-key table in `stack/README.md`. Cells are mutually isolated; a bad apply in one never blocks another. Restrict each CI role to its own `<team>/<environment>/*` prefix for defense in depth. State migration history lives at the bottom of `stack/README.md`.