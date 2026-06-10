variable "aws_region" {
  description = "AWS region for the Arbiter foundation environment."
  type        = string
  default     = "us-east-1"
}

provider "aws" {
  region = var.aws_region
}
