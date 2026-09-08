# S3 Module

Creates **one** S3 bucket, scoped as `public` or `private`. The final bucket name is **composed by the module**, enforcing the naming convention structurally, so that a team cannot produce an out-of-convention name. Looping over multiple buckets happens at the root level (`stack/s3`), not inside the module.

## Naming convention

`<environment>-<name>` — e.g. `environment = "dev"`, `name = "user-service"` → bucket `dev-user-service`.

- The environment prefix keeps environments apart within an account.
- The name is the logical service name and deliberately carries **no team**: bucket/service ownership can transfer between teams without renaming or migrating data. Ownership transfer is a config + state change, not a rename.
- Because team is absent from bucket names, two teams claiming the same name in one environment cannot be caught structurally (each team's state is isolated); CI validates cross-team uniqueness instead (`scripts/validate_team_configs.py`).

## Usage

```hcl
module "bucket" {
  source = "../module/s3"

  environment = "dev"
  name        = "user-service"
  scope       = "private" # public | private
  tags        = { Team = "a" }
}
```

## Behavior

- All buckets: versioning enabled, AES256 SSE, `BucketOwnerEnforced` ownership
- `private` scope: full public access block + bucket policy denying any non-TLS access
- `public` scope: ACL-based exposure blocked, bucket policy allowing public `s3:GetObject` (still TLS-only)
- Check block asserts the composed name fits S3's 63-character limit

## Inputs

| Name          | Type | Description |
| ------------- | ---- | ----------- |
| `name`        | string | Logical bucket name (lowercase/hyphens, must start/end alphanumeric) |
| `environment` | string | Environment prefix (e.g. `dev`, `staging`, `prod`) |
| `scope`       | string | `public` or `private` |
| `tags`        | map(string) | Tags to apply |

## Outputs

| Name         | Description |
| ------------ | ----------- |
| `bucket_id`  | Bucket ID   |
| `bucket_arn` | Bucket ARN  |