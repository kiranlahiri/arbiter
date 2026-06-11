locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "kafka" {
  name        = "${local.name_prefix}-kafka"
  description = "Security group for the Kafka broker EC2 instance."
  vpc_id      = var.vpc_id

  ingress {
    description     = "Allow Kafka broker traffic from internal application workloads."
    from_port       = var.kafka_port
    to_port         = var.kafka_port
    protocol        = "tcp"
    security_groups = [var.app_internal_security_group_id]
  }

  dynamic "ingress" {
    for_each = length(var.admin_cidrs) > 0 ? [1] : []
    content {
      description = "Allow SSH from approved admin CIDRs."
      from_port   = var.ssh_port
      to_port     = var.ssh_port
      protocol    = "tcp"
      cidr_blocks = var.admin_cidrs
    }
  }

  egress {
    description = "Allow all outbound traffic."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-kafka-sg"
    Tier = "messaging"
  })
}

resource "aws_instance" "kafka" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.kafka_instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.kafka.id]
  key_name                    = var.key_name
  associate_public_ip_address = var.assign_public_ip
  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    kafka_version         = var.kafka_version
    kafka_scala_version   = var.kafka_scala_version
    kafka_port            = var.kafka_port
    kafka_controller_port = var.kafka_controller_port
    kafka_data_dir        = var.kafka_data_dir
  })

  root_block_device {
    volume_type = "gp3"
    volume_size = var.kafka_root_volume_size_gb
    encrypted   = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-kafka"
    Role = "kafka-broker"
  })
}
