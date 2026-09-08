variable "environment" {
  description = "Environment prefix for composed bucket ARNs (matches module/s3's naming convention)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "bucket_names" {
  description = "Logical bucket names the preset grants access to. ARNs are composed as <environment>-<name>, matching module/s3's naming convention."
  type        = list(string)

  validation {
    condition = alltrue([
      for n in var.bucket_names : can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", n))
    ])
    error_message = "every bucket name must contain only lowercase letters, numbers, and hyphens, and must start and end with a letter or number."
  }
}