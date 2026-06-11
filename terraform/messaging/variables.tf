variable "aws_region" {
  description = "AWS region for the Arbiter messaging environment."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for tagging and naming messaging resources."
  type        = string
  default     = "arbiter"
}

variable "environment" {
  description = "Environment name for the messaging layer."
  type        = string
  default     = "dev"
}

variable "vpc_id" {
  description = "VPC ID from the foundation layer."
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID where the Kafka EC2 instance will be placed."
  type        = string
}

variable "app_internal_security_group_id" {
  description = "Internal application security group ID from the foundation layer."
  type        = string
}

variable "admin_cidrs" {
  description = "Optional CIDR blocks allowed to SSH to the Kafka instance."
  type        = list(string)
  default     = []
}

variable "kafka_port" {
  description = "TCP port used by the Kafka broker."
  type        = number
  default     = 9092
}

variable "ssh_port" {
  description = "TCP port used for SSH administration."
  type        = number
  default     = 22
}

variable "kafka_instance_type" {
  description = "Planned EC2 instance type for the Kafka broker."
  type        = string
  default     = "t3.small"
}

variable "kafka_root_volume_size_gb" {
  description = "Planned root or data volume size for the Kafka broker."
  type        = number
  default     = 20
}

variable "assign_public_ip" {
  description = "Whether the planned Kafka EC2 instance should receive a public IP."
  type        = bool
  default     = true
}

variable "kafka_version" {
  description = "Apache Kafka version to install on the broker."
  type        = string
  default     = "3.7.1"
}

variable "kafka_scala_version" {
  description = "Scala build suffix for the Kafka distribution tarball."
  type        = string
  default     = "2.13"
}

variable "kafka_data_dir" {
  description = "Data directory for Kafka log segments and metadata."
  type        = string
  default     = "/var/lib/kafka/data"
}

variable "kafka_controller_port" {
  description = "Controller listener port for the single-node KRaft broker."
  type        = number
  default     = 9093
}

variable "key_name" {
  description = "Optional EC2 key pair name for SSH access."
  type        = string
  default     = null
}
