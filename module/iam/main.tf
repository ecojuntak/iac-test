locals {
  # Naming convention: <team>-<environment>-<name>. A role is the team's
  # access identity, so it must carry the team (unlike buckets, which are
  # service-named and team-agnostic). IAM names are account-global, so the
  # full prefix keeps cells from fighting over one role. The team never
  # controls the composed form.
  name = "${var.team}-${var.environment}-${var.role_name}"

  # Default trust policy: EC2 service assume-role. Rendered with jsonencode
  # (no provider data source) so the module stays provider-light.
  default_trust = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = "sts:AssumeRole"
        Principal = { Service = "ec2.amazonaws.com" }
      }
    ]
  })

  trust_policy = coalesce(var.assume_role_policy, local.default_trust)
}

# Guardrail: the composed role name must fit IAM's 64-character limit. A
# check block (not a variable validation) because the length spans variables.
check "role_name_length" {
  assert {
    condition     = length(local.name) <= 64
    error_message = "composed role name exceeds the 64-character IAM limit; shorten the team, environment, or role name."
  }
}

resource "aws_iam_role" "this" {
  name               = local.name
  assume_role_policy = local.trust_policy
}

# One managed-by-Terraform inline policy per entry in policy_documents.
# The composition root (stack/iam) renders the policy JSON from the team's
# declared access; this module only attaches it and stays agnostic of
# service types.
resource "aws_iam_role_policy" "this" {
  for_each = var.policy_documents

  name   = each.key
  role   = aws_iam_role.this.id
  policy = each.value
}
