variable "team" {
  description = "Team name. Locates the team's per-env config and isolates state."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.team))
    error_message = "team must contain only lowercase letters, numbers, and hyphens, and must start and end with a letter or number."
  }
}

variable "environment" {
  description = "Environment name (the team config file without .yaml)."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "ap-southeast-1"
}

locals {
  config    = yamldecode(file("${path.module}/../../teams/${var.team}/${var.environment}.yaml"))
  s3        = try(local.config.s3, {})
  team_tags = { Team = var.team }

  # Declared buckets for this (team, environment) cell. The single source of
  # truth for bucket names; the role never re-declares them.
  declared_buckets = [for b in try(local.s3.buckets, []) : b.name]

  # The logical role name; module/iam composes <team>-<environment>-<name>.
  role = try(local.s3.role, {})
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.team_tags
  }
}

# Composition: this root reads the team's declared access and feeds each
# service's access module (module/access/<service>), which owns that service's
# naming convention, action preset, and policy rendering; module/iam composes
# the role name and attaches the rendered documents. Adding a resource type
# (e.g. RDS) means shipping module/access/rds and one entry in the role's
# policy_documents map - module/iam never changes.

module "s3_access" {
  source = "../../module/access/s3"

  environment  = var.environment
  bucket_names = local.declared_buckets
}

module "role" {
  source = "../../module/iam"

  team        = var.team
  environment = var.environment
  role_name   = try(local.role.name, "")

  assume_role_policy = try(local.role.assume_role_policy, null)

  policy_documents = {
    s3-access = module.s3_access.policy
  }
}

output "principal_arn" {
  description = "Role ARN"
  value       = module.role.arn
}