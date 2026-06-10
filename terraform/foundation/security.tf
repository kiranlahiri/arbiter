resource "aws_security_group" "public_entry" {
  name        = "${local.name_prefix}-public-entry"
  description = "Public-facing entry security group for later internet-facing services."
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow HTTP from the internet."
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS from the internet."
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-entry-sg"
    Tier = "public"
  })
}

resource "aws_security_group" "app_internal" {
  name        = "${local.name_prefix}-app-internal"
  description = "Internal application security group for later ECS or app workloads."
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Allow all outbound traffic."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-app-internal-sg"
    Tier = "private"
  })
}
