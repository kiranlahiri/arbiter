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

variable "detector_image_uri" {
  description = "Full container image URI for the detector service."
  type        = string
  default     = ""
}

variable "normalizer_image_uri" {
  description = "Full container image URI for the normalizer service image shared by Coinbase and Kraken normalizers."
  type        = string
  default     = ""
}

variable "ingestor_coinbase_image_uri" {
  description = "Full container image URI for the Coinbase ingestor service."
  type        = string
  default     = ""
}

variable "ingestor_kraken_image_uri" {
  description = "Full container image URI for the Kraken ingestor service."
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

variable "normalized_ticks_topic" {
  description = "Kafka topic where normalized ticks are published."
  type        = string
  default     = "normalized.ticks"
}

variable "raw_ticks_coinbase_topic" {
  description = "Kafka topic where Coinbase raw ticks are published."
  type        = string
  default     = "raw.ticks.coinbase"
}

variable "raw_ticks_kraken_topic" {
  description = "Kafka topic where Kraken raw ticks are published."
  type        = string
  default     = "raw.ticks.kraken"
}

variable "normalizer_coinbase_group_id" {
  description = "Kafka consumer group ID for the Coinbase normalizer service."
  type        = string
  default     = "arbiter-normalizer"
}

variable "normalizer_kraken_group_id" {
  description = "Kafka consumer group ID for the Kraken normalizer service."
  type        = string
  default     = "arbiter-normalizer-kraken"
}

variable "normalizer_start_offset" {
  description = "Kafka start offset policy for both normalizer services."
  type        = string
  default     = "latest"
}

variable "normalizer_debug" {
  description = "Whether to enable verbose debug logging in the normalizer services."
  type        = bool
  default     = false
}

variable "normalizer_log_every_n" {
  description = "Emit a periodic progress log every N processed messages in the normalizer services."
  type        = number
  default     = 25
}

variable "normalizer_cpu" {
  description = "CPU units for each normalizer task."
  type        = number
  default     = 256
}

variable "normalizer_memory" {
  description = "Memory in MiB for each normalizer task."
  type        = number
  default     = 512
}

variable "normalizer_coinbase_desired_count" {
  description = "Desired number of Coinbase normalizer tasks."
  type        = number
  default     = 1
}

variable "normalizer_kraken_desired_count" {
  description = "Desired number of Kraken normalizer tasks."
  type        = number
  default     = 1
}

variable "coinbase_product_id" {
  description = "Coinbase product ID subscribed to by the Coinbase ingestor."
  type        = string
  default     = "BTC-USD"
}

variable "coinbase_ws_url" {
  description = "Coinbase websocket endpoint used by the Coinbase ingestor."
  type        = string
  default     = "wss://ws-feed.exchange.coinbase.com"
}

variable "kraken_symbol" {
  description = "Kraken symbol subscribed to by the Kraken ingestor."
  type        = string
  default     = "BTC/USD"
}

variable "kraken_ws_url" {
  description = "Kraken websocket endpoint used by the Kraken ingestor."
  type        = string
  default     = "wss://ws.kraken.com/v2"
}

variable "ingestor_debug" {
  description = "Whether to enable verbose debug logging in the ingestor services."
  type        = bool
  default     = false
}

variable "ingestor_cpu" {
  description = "CPU units for each ingestor task."
  type        = number
  default     = 256
}

variable "ingestor_memory" {
  description = "Memory in MiB for each ingestor task."
  type        = number
  default     = 512
}

variable "ingestor_coinbase_desired_count" {
  description = "Desired number of Coinbase ingestor tasks."
  type        = number
  default     = 1
}

variable "ingestor_kraken_desired_count" {
  description = "Desired number of Kraken ingestor tasks."
  type        = number
  default     = 1
}

variable "detector_group_id" {
  description = "Kafka consumer group ID for the detector service."
  type        = string
  default     = "arbiter-detector"
}

variable "detector_start_offset" {
  description = "Kafka start offset policy for detector."
  type        = string
  default     = "latest"
}

variable "detector_min_signal_profit" {
  description = "Minimum fee-adjusted profit required before detector emits a signal."
  type        = number
  default     = 0
}

variable "detector_fee_bps" {
  description = "Fee rate in basis points used by detector when computing fee-adjusted profit."
  type        = number
  default     = 0
}

variable "detector_max_quote_age_ms" {
  description = "Maximum age in milliseconds for quotes considered by detector."
  type        = number
  default     = 5000
}

variable "detector_max_quote_gap_ms" {
  description = "Maximum allowed gap in milliseconds between paired quotes."
  type        = number
  default     = 500
}

variable "detector_min_signal_interval_ms" {
  description = "Minimum interval in milliseconds between repeated signals for the same route."
  type        = number
  default     = 500
}

variable "detector_debug" {
  description = "Whether to enable verbose debug logging in detector."
  type        = bool
  default     = false
}

variable "detector_cpu" {
  description = "CPU units for the detector task."
  type        = number
  default     = 256
}

variable "detector_memory" {
  description = "Memory in MiB for the detector task."
  type        = number
  default     = 512
}

variable "detector_desired_count" {
  description = "Desired number of detector tasks."
  type        = number
  default     = 1
}
