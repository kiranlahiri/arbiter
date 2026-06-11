variable "aws_region" {
  description = "AWS region for the Arbiter app environment."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for tagging and naming app resources."
  type        = string
  default     = "arbiter"
}

variable "environment" {
  description = "Environment name for the app layer."
  type        = string
  default     = "dev"
}

variable "vpc_id" {
  description = "VPC ID from the foundation layer."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs from the foundation layer."
  type        = list(string)
}

variable "public_entry_security_group_id" {
  description = "Public entry security group ID from the foundation layer."
  type        = string
}

variable "api_container_port" {
  description = "Container port the API listens on."
  type        = number
  default     = 8080
}
