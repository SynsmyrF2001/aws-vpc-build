terraform {
  required_version = ">= 1.10.0" # native S3 locking (use_lockfile) needs 1.10+

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Partial backend config: `bucket` is supplied at init time from
  # backend.hcl (gitignored) rather than hardcoded here, because the bucket
  # name embeds the AWS account ID and this repo is public. Backend blocks
  # can't reference variables or data sources, so a -backend-config file is
  # the only way to keep it out of source.
  #   terraform init -backend-config=backend.hcl
  # See backend.hcl.example for the shape.
  backend "s3" {
    key          = "aws-vpc-build/terraform.tfstate"
    region       = "us-east-1"
    profile      = "vpc-project" # backend blocks don't inherit from provider blocks —
                                  # this needs its own credential config, separately
    use_lockfile = true          # native S3 locking — no DynamoDB table needed
    encrypt      = true
  }
}

provider "aws" {
  region  = "us-east-1"
  profile = "vpc-project"

  default_tags {
    tags = {
      Project   = "aws-vpc-build"
      ManagedBy = "terraform"
    }
  }
}
