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
  buckets   = try(local.config.s3.buckets, [])
  team_tags = { Team = var.team }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.team_tags
  }
}

module "s3" {
  source = "../../module/s3"

  for_each = { for b in local.buckets : b.name => b }

  environment = var.environment
  name        = each.value.name
  scope       = each.value.scope
  tags        = local.team_tags
}

output "bucket_arns" {
  description = "Map of bucket names to ARNs (consumed by stack/iam)"
  value       = { for k, v in module.s3 : k => v.bucket_arn }
}
