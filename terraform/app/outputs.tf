output "ecs_cluster_name" {
  description = "ECS cluster name for the app layer."
  value       = aws_ecs_cluster.main.name
}

output "api_service_security_group_id" {
  description = "Security group ID for API ECS tasks."
  value       = aws_security_group.api_service.id
}

output "api_log_group_name" {
  description = "CloudWatch log group for the API service."
  value       = aws_cloudwatch_log_group.api.name
}

output "alb_dns_name" {
  description = "DNS name for the API application load balancer."
  value       = aws_lb.api.dns_name
}

output "alb_target_group_arn" {
  description = "Target group ARN for the API service."
  value       = aws_lb_target_group.api.arn
}

output "api_service_name" {
  description = "ECS service name for the API."
  value       = aws_ecs_service.api.name
}

output "signal_writer_service_name" {
  description = "ECS service name for signal-writer."
  value       = aws_ecs_service.signal_writer.name
}

output "api_task_definition_arn" {
  description = "Task definition ARN for the API service."
  value       = aws_ecs_task_definition.api.arn
}

output "database_url_secret_arn" {
  description = "Secrets Manager ARN for the API DATABASE_URL secret."
  value       = aws_secretsmanager_secret.database_url.arn
}

output "database_url_secret_name" {
  description = "Secrets Manager name for the API DATABASE_URL secret."
  value       = aws_secretsmanager_secret.database_url.name
}

output "signal_writer_log_group_name" {
  description = "CloudWatch log group for the signal-writer service."
  value       = aws_cloudwatch_log_group.signal_writer.name
}
