# ============================================================
# main.tf
# This is the ENTRY POINT of our Terraform project.
# It does 2 things:
#   1. Tells Terraform which version to use
#   2. Tells Terraform which cloud to talk to (AWS)
# ============================================================


# This block configures Terraform itself (not AWS)
terraform {

  # Minimum Terraform version required to run this code
  required_version = ">= 1.5.0"

  # "Providers" are plugins that let Terraform talk to different clouds.
  # We only need the AWS provider since we're deploying to AWS.
  required_providers {
    aws = {
      source  = "hashicorp/aws" # Download from the official HashiCorp registry
      version = "~> 5.0"        # Use any version 5.x (e.g. 5.1, 5.20, etc.)
    }
  }
}


# This block tells the AWS provider:
#   - Which region to deploy resources in
#   - What tags to automatically add to EVERY resource we create
provider "aws" {
  region = var.aws_region # comes from variables.tf → set in terraform.tfvars

  # default_tags = tags applied to every single AWS resource automatically
  # This makes it easy to find all resources belonging to this project
  # in the AWS console, and also helps with billing breakdowns
  default_tags {
    tags = {
      Project   = "wanderlust" # Our app name
      ManagedBy = "terraform"  # Reminds us not to edit these manually in AWS console
    }
  }
}


# These two "data" blocks don't CREATE anything.
# They just READ existing info from AWS and make it available to use elsewhere.

# Gets the AWS Account ID of whoever is running terraform apply
# (useful in outputs and for building ARNs)
data "aws_caller_identity" "current" {}

# Gets the current AWS region (same as var.aws_region, but fetched from AWS directly)
data "aws_region" "current" {}
