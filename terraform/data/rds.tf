locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_security_group" "postgres" {
  name        = "${local.name_prefix}-postgres"
  description = "Security group for the Arbiter PostgreSQL instance."
  vpc_id      = var.vpc_id

  ingress {
    description     = "Allow PostgreSQL access from internal app workloads."
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.app_internal_security_group_id]
  }

  egress {
    description = "Allow all outbound traffic."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-postgres-sg"
  })
}

resource "aws_db_subnet_group" "postgres" {
  name       = "${local.name_prefix}-postgres"
  subnet_ids = var.private_subnet_ids

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-postgres-subnet-group"
  })
}

resource "aws_db_instance" "postgres" {
  identifier              = "${local.name_prefix}-postgres"
  engine                  = "postgres"
  engine_version          = "16.3"
  instance_class          = var.db_instance_class
  allocated_storage       = var.db_allocated_storage
  max_allocated_storage   = var.db_allocated_storage + 20
  db_name                 = var.db_name
  username                = var.db_username
  password                = var.db_password
  db_subnet_group_name    = aws_db_subnet_group.postgres.name
  vpc_security_group_ids  = [aws_security_group.postgres.id]
  backup_retention_period = 7
  deletion_protection     = false
  skip_final_snapshot     = true
  multi_az                = var.db_multi_az
  publicly_accessible     = false
  storage_encrypted       = true
  apply_immediately       = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-postgres"
  })
}
