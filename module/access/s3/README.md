# S3 Access Module

Renders the **S3 access preset** — what "access to a team's buckets" means — as an IAM policy document. It composes bucket ARNs as `<environment>-<name>` (the naming convention `module/s3` enforces) from the logical bucket names the composition root passes in, and grants them exactly the fixed object-level action set. The module declares no provider and creates no resources: it is the *access* half of the composition; the composition root (`stack/iam`) feeds its output to `module/iam`, which attaches it.

## Usage

```hcl
module "s3_access" {
  source = "../module/access/s3"

  environment  = "prod"
  bucket_names = ["user-service", "order-service"]
}
```

## Behavior

- Bucket ARNs are composed as `arn:aws:s3:::<environment>-<name>` and `arn:aws:s3:::<environment>-<name>/*` — buckets carry no team (ownership is transferable), so ARNs need only the environment prefix
- Exactly the fixed object-level action preset: `GetObject`, `GetObjectVersion`, `ListBucket`, `PutObject`, `DeleteObject`
- No bucket-level configuration actions (`PutBucket`, `DeleteBucket`, ...): bucket guardrails are platform-owned in `module/s3`, so teams cannot mutate them; the requirement is binary (a role reaches its team's buckets or it doesn't), so there is no per-team level selector

## Inputs

| Name          | Type         | Description                                                        |
| ------------- | ------------ | ------------------------------------------------------------------ |
| `environment` | string       | Environment prefix for composed ARNs (`dev`, `staging`, `prod`)    |
| `bucket_names`| list(string) | Logical bucket names to grant access to (ARNs composed from these) |

## Outputs

| Name      | Description                                              |
| --------- | -------------------------------------------------------- |
| `actions` | The fixed S3 action preset granted to a team's role      |
| `policy`  | Rendered S3 access policy document (JSON), scoped to the composed ARNs |