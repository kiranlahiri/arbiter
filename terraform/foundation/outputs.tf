output "vpc_id" {
  description = "ID of the Arbiter foundation VPC."
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block assigned to the Arbiter foundation VPC."
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets."
  value       = [for subnet in aws_subnet.public : subnet.id]
}

output "private_subnet_ids" {
  description = "IDs of the private subnets."
  value       = [for subnet in aws_subnet.private : subnet.id]
}

output "public_route_table_id" {
  description = "Route table ID used by the public subnets."
  value       = aws_route_table.public.id
}

output "private_route_table_id" {
  description = "Route table ID used by the private subnets."
  value       = aws_route_table.private.id
}

output "internet_gateway_id" {
  description = "Internet gateway attached to the Arbiter VPC."
  value       = aws_internet_gateway.main.id
}

output "public_entry_security_group_id" {
  description = "Security group ID for public-facing entry traffic."
  value       = aws_security_group.public_entry.id
}

output "app_internal_security_group_id" {
  description = "Security group ID for internal app traffic."
  value       = aws_security_group.app_internal.id
}

output "ecr_repository_urls" {
  description = "ECR repository URLs keyed by service name."
  value = {
    for service, repo in aws_ecr_repository.service :
    service => repo.repository_url
  }
}
