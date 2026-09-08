# iac — Terraform Infrastructure

Declarative AWS infrastructure for all product teams. Teams declare *what* they need in one YAML file per environment; the platform owns *how* it is provisioned — naming conventions, guardrails, and IAM are structural, not documentation.

```
teams/     <team>/<environment>.yaml — the only files teams edit
schema/    JSON schema every team config validates against
stack/     per-component Terraform roots (s3, iam) shared by all teams
module/    reusable building blocks (s3, iam, access/<service>)
scripts/   repo-level config validation (CI gate)
```

---

## Guide for product teams

You manage **one file per environment**: `teams/<your-team>/<environment>.yaml` (`dev`, `staging`, `prod`). You never write Terraform, never touch `stack/` or `module/`, and never see state. CI plans on your PR and applies on merge.

### Declaring resources

```yaml
# yaml-language-server: $schema=../../schema/schema.json
s3:
  role:
    name: app              # your team's access identity (logical name only)
  buckets:
    - name: user-service   # logical name; must be unique across ALL teams in this environment
      scope: private       # private = fully public-blocked, public = anonymous read allowed
    - name: invoice-service
      scope: private
```

What you get, without asking:

- **Buckets** named `<environment>-<name>` (e.g. `prod-user-service`) with versioning, AES256 encryption at rest, and TLS-only enforced. `private` blocks all public access; `public` allows anonymous `s3:GetObject` and nothing else.
- **One IAM role** per team × environment (e.g. `commerce-prod-app`), trusted by EC2, that can reach *exactly your declared buckets* — nothing shared, nothing missing. Access is implicit: adding a bucket grants it to your role automatically; removing one revokes it. No policy files to keep in sync.
- Grants are **object-level only** (`GetObject`, `GetObjectVersion`, `ListBucket`, `PutObject`, `DeleteObject`). Bucket configuration (policies, ACLs, deletion) is platform-owned — your role cannot modify guardrails applied to your own buckets.

### Common tasks

| Task | How |
|------|-----|
| Add a bucket | Append an entry under `s3.buckets`, open a PR |
| Remove a bucket | Delete the entry, open a PR. Applies fail if the bucket still contains objects — empty it first (this is a deliberate guardrail, not a bug) |
| Rename your role | Change `s3.role.name` — this recreates the role; coordinate with platform |
| Onboard a new environment | Add `<environment>.yaml` to your team directory; coordinate with platform |
| Preview your change | The PR comment shows `terraform plan` for every affected cell |

### Rules the platform enforces for you

- Bucket names must be **unique across all teams within an environment** (they are team-agnostic so ownership can transfer without renaming). `scripts/validate_team_configs.py` fails your PR if you collide with another team.
- Names are lowercase alphanumeric + hyphens (same pattern as DNS), 1–63 chars.
- Every environment file must validate against `schema/schema.json` — your editor validates live via the `$schema` line.

### Deleting your environment config

Deleting `teams/<your-team>/<environment>.yaml` (or your whole team directory) on `main` triggers a managed teardown: CI runs `terraform destroy` for every component in that cell, using your config as it existed before the deletion. On a PR the same change only *previews* what would be destroyed. Do not re-add the file in the same change as deleting it — CI refuses ambiguous deletions.

---

## For the platform team

If you are contributing Terraform — stacks, modules, schema, CI — read [CONTRIBUTING.md](CONTRIBUTING.md). It covers the repository layout, the composition model (access / identity / aggregation), local workflows, CI behavior, the state model, and the recipes for extending the platform (new service, environment, or team).