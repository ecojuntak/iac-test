mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock"
    }
  }
}

run "creates_role_with_default_trust" {
  command = apply

  variables {
    team        = "commerce"
    environment = "dev"
    role_name   = "app"
  }

  assert {
    condition     = output.name == "commerce-dev-app"
    error_message = "role name must be composed as <team>-<environment>-<role_name>"
  }

  assert {
    condition     = can(jsondecode(aws_iam_role.this.assume_role_policy))
    error_message = "default trust policy must be valid JSON"
  }

  assert {
    condition     = length(aws_iam_role_policy.this) == 0
    error_message = "no inline policies must exist when policy_documents is empty"
  }
}

run "attaches_one_inline_policy_per_document" {
  command = apply

  variables {
    team        = "commerce"
    environment = "dev"
    role_name   = "app"
    policy_documents = {
      s3-access = jsonencode({
        Version   = "2012-10-17"
        Statement = [{ Effect = "Allow", Action = "s3:GetObject", Resource = "arn:aws:s3:::user-service/*" }]
      })
      extra = jsonencode({
        Version   = "2012-10-17"
        Statement = [{ Effect = "Allow", Action = "sqs:SendMessage", Resource = "*" }]
      })
    }
  }

  assert {
    condition     = length(aws_iam_role_policy.this) == 2
    error_message = "one inline policy must exist per policy_documents entry"
  }

  assert {
    condition     = aws_iam_role_policy.this["s3-access"].role == aws_iam_role.this.id
    error_message = "inline policy must be attached to the created role"
  }

  assert {
    condition     = aws_iam_role_policy.this["s3-access"].policy == var.policy_documents["s3-access"]
    error_message = "policy JSON must be attached verbatim"
  }
}

run "custom_trust_policy" {
  command = apply

  variables {
    team        = "commerce"
    environment = "dev"
    role_name   = "app"
    assume_role_policy = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect    = "Allow"
        Action    = "sts:AssumeRole"
        Principal = { Service = "eks.amazonaws.com" }
      }]
    })
  }

  assert {
    condition     = aws_iam_role.this.assume_role_policy == var.assume_role_policy
    error_message = "custom trust policy must be used verbatim"
  }
}

run "rejects_invalid_team_characters" {
  command = plan

  variables {
    team        = "invalid team"
    environment = "dev"
    role_name   = "app"
  }

  expect_failures = [
    var.team,
  ]
}

run "rejects_non_json_policy_document" {
  command = plan

  variables {
    team        = "commerce"
    environment = "dev"
    role_name   = "app"
    policy_documents = {
      broken = "this is not json"
    }
  }

  expect_failures = [
    var.policy_documents,
  ]
}