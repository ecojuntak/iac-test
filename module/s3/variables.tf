variable "name" {
  description = "Logical bucket name. The final bucket name is composed as <environment>-<name>; the team never controls the composed form."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.name))
    error_message = "name must contain only lowercase letters, numbers, and hyphens, and must start and end with a letter or number."
  }
}

variable "environment" {
  description = "Environment prefix for the composed bucket name"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "scope" {
  description = "Access scope: 'public' allows anonymous s3:GetObject, 'private' denies it"
  type        = string

  validation {
    condition     = contains(["public", "private"], var.scope)
    error_message = "scope must be either 'public' or 'private'."
  }
}

variable "tags" {
  description = "Tags to apply to the bucket"
  type        = map(string)
  default     = {}
}