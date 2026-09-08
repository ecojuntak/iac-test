# IAM Role Module

Creates one IAM role and attaches any number of IAM policy documents to it. The module is agnostic of service types: it never encodes what "S3 access" or "RDS access" means. Each service owns its access preset in `module/access/<service>`, which renders policy JSON; the composition root (`stack/iam`) feeds those documents to this module, which attaches them verbatim. Each cell (team × environment) has exactly one role, instantiated once by the root.

## Usage

```hcl
module "role" {
  source = "../module/iam"

  team        = "commerce"
  environment = "dev"
  role_name   = "app"
  policy_documents = {
    s3-access = local.s3_policy
  }
}
```

## Behavior

- Role name is composed as `<team>-<environment>-<role_name>` (a check block guards IAM's 64-character limit); the team never controls the composed form
- Trust policy defaults to an EC2 service trust unless `assume_role_policy` (JSON) is provided
- One inline policy per `policy_documents` entry, keyed by policy name
- No resource permissions are created here — the module is the *identity* half of the composition; *what* access means lives in each service's access module

## Design: why the role module has no S3 knowledge

A team's role aggregates permissions across resource types (S3 today, RDS tomorrow). Keeping role creation generic means adding a new resource type is purely additive: the resource module ships, its access module renders the policy, both are attached to the same role, and `module/iam` never changes.

## Inputs

| Name                 | Type        | Description                                       |
| -------------------- | ----------- | ------------------------------------------------- |
| `team`               | string      | Team prefix for the composed role name            |
| `environment`        | string      | Environment prefix for the composed role name     |
| `role_name`          | string      | Logical role name (composed as `<team>-<environment>-<role_name>`) |
| `assume_role_policy` | string      | Trust policy JSON (default: EC2 service trust)   |
| `policy_documents`   | map(string) | Inline policy name -> IAM policy document (JSON) |

## Outputs

| Name   | Description |
| ------ | ----------- |
| `arn`  | Role ARN    |
| `name` | Role name   |