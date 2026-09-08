# S3 access preset: what "access to this team's buckets" means, fixed at the
# platform level. The composition root (stack/iam) supplies the declared
# bucket names; this module composes the ARNs and owns all other S3-specific
# policy knowledge.

locals {
  # Bucket ARNs are composed as <environment>-<name>, matching the naming
  # convention module/s3 enforces. Buckets are named after the service and
  # deliberately carry no team (ownership can transfer between teams);
  # roles are named after the team (the access grantee). That asymmetry is
  # why bucket ARNs need only the environment prefix.
  bucket_resources = flatten([
    for n in var.bucket_names : [
      "arn:aws:s3:::${var.environment}-${n}",
      "arn:aws:s3:::${var.environment}-${n}/*"
    ]
  ])

  # Fixed object-level action preset. Object-level only: bucket-level
  # configuration (policy, ACL, deletion) stays platform-owned in module/s3,
  # so teams cannot mutate the guardrails applied to their own buckets.
  actions = [
    "s3:GetObject",
    "s3:GetObjectVersion",
    "s3:ListBucket",
    "s3:PutObject",
    "s3:DeleteObject",
  ]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = local.actions
        Resource = local.bucket_resources
      }
    ]
  })
}
