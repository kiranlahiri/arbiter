output "kafka_security_group_id" {
  description = "Security group ID for the Kafka broker."
  value       = aws_security_group.kafka.id
}

output "kafka_subnet_id" {
  description = "Subnet selected for the Kafka broker."
  value       = var.subnet_id
}

output "kafka_instance_id" {
  description = "EC2 instance ID for the Kafka broker."
  value       = aws_instance.kafka.id
}

output "kafka_private_ip" {
  description = "Private IP address of the Kafka broker."
  value       = aws_instance.kafka.private_ip
}

output "kafka_public_ip" {
  description = "Public IP address of the Kafka broker, if assigned."
  value       = aws_instance.kafka.public_ip
}

output "kafka_broker_endpoint" {
  description = "Broker endpoint string to use from other AWS workloads."
  value       = "${aws_instance.kafka.private_ip}:${var.kafka_port}"
}
