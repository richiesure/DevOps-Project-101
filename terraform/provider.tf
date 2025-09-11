provider "aws" {
  region = var.aws_region
}

# Helpful identity output on apply
data "aws_caller_identity" "current" {}
