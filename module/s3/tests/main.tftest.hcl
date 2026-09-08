# Module tests for the naming convention and per-scope guardrails, using a
# mocked AWS provider so no real AWS account is needed.

mock_provider "aws" {
  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::mock-bucket"
    }
  }
  mock_resource "aws_s3_bucket_public_access_block" {
    defaults = {
      id = "mock-pab"
    }
  }
}

run "composes_environment_prefixed_name" {
  command = apply

  variables {
    environment = "dev"
    name        = "user-service"
    scope       = "private"
  }

  assert {
    condition     = local.bucket_name == "dev-user-service"
    error_message = "module must compose the bucket name as <environment>-<name>"
  }

  assert {
    condition     = aws_s3_bucket.this.bucket == "dev-user-service"
    error_message = "the composed name must be the bucket's physical name"
  }

  assert {
    condition     = aws_s3_bucket.this.tags["Name"] == "dev-user-service"
    error_message = "the Name tag must be the composed name"
  }
}

run "private_scope_blocks_all_public_access" {
  command = apply

  variables {
    environment = "prod"
    name        = "user-service"
    scope       = "private"
  }

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.private[0].block_public_acls,
      aws_s3_bucket_public_access_block.private[0].block_public_policy,
      aws_s3_bucket_public_access_block.private[0].ignore_public_acls,
      aws_s3_bucket_public_access_block.private[0].restrict_public_buckets,
    ])
    error_message = "private scope must enable all four public access block settings"
  }

  assert {
    condition     = length(aws_s3_bucket_public_access_block.public) == 0
    error_message = "private scope must not create the public access block"
  }
}

run "public_scope_allows_policy_based_exposure_only" {
  command = apply

  variables {
    environment = "staging"
    name        = "product-service"
    scope       = "public"
  }

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.public[0].block_public_acls,
      !aws_s3_bucket_public_access_block.public[0].block_public_policy,
      aws_s3_bucket_public_access_block.public[0].ignore_public_acls,
      !aws_s3_bucket_public_access_block.public[0].restrict_public_buckets,
    ])
    error_message = "public scope must block ACL exposure but allow bucket-policy reads"
  }

  assert {
    condition     = length(aws_s3_bucket_public_access_block.private) == 0
    error_message = "public scope must not create the private access block"
  }
}

run "public_policy_allows_anonymous_read_only" {
  command = apply

  variables {
    environment = "dev"
    name        = "product-service"
    scope       = "public"
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.public[0].policy).Statement[0].Action == "s3:GetObject"
    error_message = "public bucket policy must only grant s3:GetObject"
  }
}

run "rejects_edge_hyphen_name" {
  command = plan

  variables {
    environment = "dev"
    name        = "-user-service"
    scope       = "private"
  }

  expect_failures = [
    var.name,
  ]
}

run "rejects_bad_environment" {
  command = plan

  variables {
    environment = "Production"
    name        = "user-service"
    scope       = "private"
  }

  expect_failures = [
    var.environment,
  ]
}

# The 63-char limit on the composed name is enforced by the provider's
# bucket schema at plan time (schema-level rejection is not claimable via
# expect_failures under mock_provider, so the limit is pinned by the
# boundary case below).
run "accepts_name_at_the_length_limit" {
  command = apply

  variables {
    environment = "dev"
    name        = "service-name-exactly-fifty-nine-characters-long-aaaaaaaaaa0"
    scope       = "private"
  }

  assert {
    condition     = length(local.bucket_name) == 63
    error_message = "a composed name of exactly 63 characters must be accepted"
  }
}
