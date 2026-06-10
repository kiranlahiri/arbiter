variable "project_name" {
  description = "Project name used for tagging and naming foundation resources."
  type        = string
  default     = "arbiter"
}

variable "environment" {
  description = "Environment name for the foundation layer."
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the Arbiter VPC."
  type        = string
  default     = "10.42.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones used for the foundation subnets."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets."
  type        = list(string)
  default     = ["10.42.0.0/24", "10.42.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets."
  type        = list(string)
  default     = ["10.42.10.0/24", "10.42.11.0/24"]
}
