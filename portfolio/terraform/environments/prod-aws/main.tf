# Example environment: a production AWS VPC built from the reusable module.
# Backend and provider credentials come from the environment / CI (never committed).
terraform {
  required_version = ">= 1.11" # S3-native state locking (use_lockfile)
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40, < 7.0"
    }
  }

  # Configure in backend.hcl (terraform init -backend-config=backend.hcl):
  #   bucket = "pdi-tfstate"  key = "prod-aws/terraform.tfstate"  region = "us-east-2"  use_lockfile = true
  # (DynamoDB locking via dynamodb_table is deprecated.) Enable versioning on the state bucket.
  backend "s3" {}
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project   = "pdi-platform"
      ManagedBy = "terraform"
      Env       = "prod"
    }
  }
}

variable "region" {
  type    = string
  default = "us-east-2"
}

module "vpc" {
  source     = "../../modules/aws-vpc"
  name       = "prod"
  cidr_block = "10.40.0.0/16"
  az_count   = 2

  enable_nat_gateway = true
  single_nat_gateway = false
  enable_flow_logs   = true

  tags = {
    Owner = "platform-team"
  }
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}
