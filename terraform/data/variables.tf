variable "aws_region" {
  description = "AWS region for the Arbiter data environment."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for tagging and naming data resources."
  type        = string
  default     = "arbiter"
}

variable "environment" {
  description = "Environment name for the data layer."
  type        = string
  default     = "dev"
}

variable "vpc_id" {
  description = "VPC ID from the foundation layer."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs from the foundation layer."
  type        = list(string)
}

variable "app_internal_security_group_id" {
  description = "Internal app security group ID from the foundation layer."
  type        = string
}

variable "db_name" {
  description = "PostgreSQL database name."
  type        = string
  default     = "arbiter"
}

variable "db_username" {
  description = "PostgreSQL master username."
  type        = string
  default     = "arbiter"
}

variable "db_password" {
  description = "PostgreSQL master password."
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage in GB."
  type        = number
  default     = 20
}

variable "db_multi_az" {
  description = "Whether to enable Multi-AZ."
  type        = bool
  default     = false
}
