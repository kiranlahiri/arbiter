output "postgres_security_group_id" {
  description = "Security group ID for the PostgreSQL instance."
  value       = aws_security_group.postgres.id
}

output "postgres_subnet_group_name" {
  description = "DB subnet group name for the PostgreSQL instance."
  value       = aws_db_subnet_group.postgres.name
}

output "postgres_endpoint" {
  description = "DNS endpoint for the PostgreSQL instance."
  value       = aws_db_instance.postgres.address
}

output "postgres_port" {
  description = "Port for the PostgreSQL instance."
  value       = aws_db_instance.postgres.port
}

output "postgres_database_name" {
  description = "Database name configured for the PostgreSQL instance."
  value       = aws_db_instance.postgres.db_name
}
