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

variable "postgres_security_group_id" {
  description = "PostgreSQL security group ID from the data layer."
  type        = string
}

variable "kafka_security_group_id" {
  description = "Kafka security group ID from the messaging layer."
  type        = string
  default     = ""
}

variable "kafka_brokers" {
  description = "Comma-separated Kafka broker endpoints for internal worker services."
  type        = string
  default     = ""
}

variable "api_image_uri" {
  description = "Full container image URI for the API service."
  type        = string
}

variable "signal_writer_image_uri" {
  description = "Full container image URI for the signal-writer service."
  type        = string
  default     = ""
}

variable "database_url" {
  description = "Database connection string used by the API service."
  type        = string
  default     = ""
  sensitive   = true
}

variable "use_database_url_secret" {
  description = "Whether the API should read DATABASE_URL from AWS Secrets Manager instead of a plain environment variable."
  type        = bool
  default     = false
}

variable "database_url_secret_name" {
  description = "Optional override for the Secrets Manager secret name that will hold DATABASE_URL."
  type        = string
  default     = ""
}

variable "api_container_port" {
  description = "Container port the API listens on."
  type        = number
  default     = 8080
}

variable "api_cpu" {
  description = "CPU units for the API task."
  type        = number
  default     = 256
}

variable "api_memory" {
  description = "Memory in MiB for the API task."
  type        = number
  default     = 512
}

variable "api_desired_count" {
  description = "Desired number of API tasks."
  type        = number
  default     = 1
}

variable "signals_topic" {
  description = "Kafka topic where arbitrage signals are published."
  type        = string
  default     = "arbitrage.signals"
}

variable "signal_writer_group_id" {
  description = "Kafka consumer group ID for the signal-writer service."
  type        = string
  default     = "arbiter-signal-writer"
}

variable "signal_writer_start_offset" {
  description = "Kafka start offset policy for signal-writer."
  type        = string
  default     = "latest"
}

variable "signal_writer_cpu" {
  description = "CPU units for the signal-writer task."
  type        = number
  default     = 256
}

variable "signal_writer_memory" {
  description = "Memory in MiB for the signal-writer task."
  type        = number
  default     = 512
}

variable "signal_writer_desired_count" {
  description = "Desired number of signal-writer tasks."
  type        = number
  default     = 1
}
