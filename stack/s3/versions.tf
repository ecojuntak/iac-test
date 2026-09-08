terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  backend "s3" {
    # Values supplied via -backend-config flags in CI:
    #   bucket=<state-bucket>
    #   key=<team>/<environment>/s3.tfstate
    #   region=<region>
    #   dynamodb_table=<lock-table>
  }
}