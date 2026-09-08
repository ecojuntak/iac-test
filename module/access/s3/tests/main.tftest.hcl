# Module tests for the S3 access preset: ARN composition per the naming
# convention, the exact action set, its object-level-only shape, and the
# rendered policy's structure. The module declares no provider and creates no
# resources, so no provider mock is needed.

run "composes_environment_prefixed_bucket_arns" {
  command = plan

  variables {
    environment  = "prod"
    bucket_names = ["user-service", "order-service"]
  }

  assert {
    condition = toset(jsondecode(output.policy).Statement[0].Resource) == toset([
      "arn:aws:s3:::prod-user-service",
      "arn:aws:s3:::prod-user-service/*",
      "arn:aws:s3:::prod-order-service",
      "arn:aws:s3:::prod-order-service/*",
    ])
    error_message = "policy must cover bucket and object ARNs of every declared bucket, environment-prefixed per the naming convention"
  }
}

run "policy_is_the_fixed_object_level_action_preset" {
  command = plan

  variables {
    environment  = "dev"
    bucket_names = ["user-service"]
  }

  assert {
    condition = toset(jsondecode(output.policy).Statement[0].Action) == toset([
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:ListBucket",
      "s3:PutObject",
      "s3:DeleteObject",
    ])
    error_message = "policy must be exactly the fixed object-level action preset"
  }

  assert {
    condition = alltrue([
      for a in jsondecode(output.policy).Statement[0].Action :
      !startswith(a, "s3:PutBucket") && !startswith(a, "s3:DeleteBucket")
    ])
    error_message = "policy must never grant bucket-level configuration actions"
  }

  assert {
    condition     = jsondecode(output.policy).Statement[0].Effect == "Allow"
    error_message = "policy statement must be an Allow"
  }

  assert {
    condition     = jsondecode(output.policy).Version == "2012-10-17"
    error_message = "policy must use the 2012-10-17 policy version"
  }
}

run "actions_output_matches_policy" {
  command = plan

  variables {
    environment  = "dev"
    bucket_names = []
  }

  assert {
    condition     = toset(output.actions) == toset(jsondecode(output.policy).Statement[0].Action)
    error_message = "the actions output must match the actions rendered into the policy"
  }
}

run "rejects_bad_environment" {
  command = plan

  variables {
    environment  = "Production"
    bucket_names = ["user-service"]
  }

  expect_failures = [
    var.environment,
  ]
}

run "rejects_bad_bucket_name" {
  command = plan

  variables {
    environment  = "dev"
    bucket_names = ["-user-service"]
  }

  expect_failures = [
    var.bucket_names,
  ]
}