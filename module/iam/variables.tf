variable "team" {
  description = "Team name prefix for the composed role name"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]+$", var.team))
    error_message = "team contains invalid IAM name characters."
  }
}

variable "environment" {
  description = "Environment prefix for the composed role name"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]+$", var.environment))
    error_message = "environment contains invalid IAM name characters."
  }
}

variable "role_name" {
  description = "Logical role name. The final role name is composed as <team>-<environment>-<role_name>; the team never controls the composed form."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]+$", var.role_name))
    error_message = "role_name contains invalid IAM name characters."
  }
}

variable "assume_role_policy" {
  description = "Trust policy JSON. Defaults to EC2 service trust."
  type        = string
  default     = null
}

variable "policy_documents" {
  description = "Map of inline policy name to IAM policy document (JSON). Rendered by each service's access module (module/access/<service>) and assembled by the composition root (stack/iam); attached verbatim."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for name, doc in var.policy_documents : can(jsondecode(doc))
    ])
    error_message = "every policy_documents value must be valid JSON."
  }
}
