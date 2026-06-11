locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  api_container_name       = "api"
  signal_writer_name       = "signal-writer"
  database_url_secret_name = trimspace(var.database_url_secret_name) != "" ? trimspace(var.database_url_secret_name) : "${local.name_prefix}/api/database-url"
}

resource "aws_security_group" "api_service" {
  name        = "${local.name_prefix}-api-service"
  description = "Security group for the API ECS tasks."
  vpc_id      = var.vpc_id

  ingress {
    description     = "Allow API traffic from the public entry security group."
    from_port       = var.api_container_port
    to_port         = var.api_container_port
    protocol        = "tcp"
    security_groups = [var.public_entry_security_group_id]
  }

  egress {
    description = "Allow all outbound traffic."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-api-service-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "postgres_from_api" {
  security_group_id            = var.postgres_security_group_id
  referenced_security_group_id = aws_security_group.api_service.id
  description                  = "Allow PostgreSQL access from the API ECS tasks."
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_security_group" "signal_writer" {
  name        = "${local.name_prefix}-signal-writer"
  description = "Security group for the signal-writer ECS tasks."
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound traffic."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-signal-writer-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "postgres_from_signal_writer" {
  security_group_id            = var.postgres_security_group_id
  referenced_security_group_id = aws_security_group.signal_writer.id
  description                  = "Allow PostgreSQL access from the signal-writer ECS tasks."
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "kafka_from_signal_writer" {
  count = trimspace(var.kafka_security_group_id) == "" ? 0 : 1

  security_group_id            = var.kafka_security_group_id
  referenced_security_group_id = aws_security_group.signal_writer.id
  description                  = "Allow Kafka access from the signal-writer ECS tasks."
  from_port                    = 9092
  to_port                      = 9092
  ip_protocol                  = "tcp"
}

resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-ecs"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ecs"
  })
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/ecs/${local.name_prefix}/api"
  retention_in_days = 14

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "signal_writer" {
  name              = "/aws/ecs/${local.name_prefix}/signal-writer"
  retention_in_days = 14

  tags = local.common_tags
}

resource "aws_lb" "api" {
  name               = substr("${local.name_prefix}-api", 0, 32)
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.public_entry_security_group_id]
  subnets            = var.public_subnet_ids

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-api"
  })
}

resource "aws_lb_target_group" "api" {
  name        = substr("${local.name_prefix}-api", 0, 32)
  port        = var.api_container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    enabled             = true
    path                = "/health"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.api.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}

data "aws_iam_policy_document" "ecs_task_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "api_execution_secrets" {
  statement {
    effect = "Allow"

    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
    ]

    resources = [aws_secretsmanager_secret.database_url.arn]
  }
}

data "aws_iam_policy_document" "signal_writer_execution_secrets" {
  statement {
    effect = "Allow"

    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
    ]

    resources = [aws_secretsmanager_secret.database_url.arn]
  }
}

resource "aws_iam_role" "api_execution" {
  name               = "${local.name_prefix}-api-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "api_execution_ecs" {
  role       = aws_iam_role.api_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "api_execution_secrets" {
  name   = "${local.name_prefix}-api-execution-secrets"
  role   = aws_iam_role.api_execution.id
  policy = data.aws_iam_policy_document.api_execution_secrets.json
}

resource "aws_iam_role" "api_task" {
  name               = "${local.name_prefix}-api-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role" "signal_writer_execution" {
  name               = "${local.name_prefix}-signal-writer-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "signal_writer_execution_ecs" {
  role       = aws_iam_role.signal_writer_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "signal_writer_execution_secrets" {
  name   = "${local.name_prefix}-signal-writer-execution-secrets"
  role   = aws_iam_role.signal_writer_execution.id
  policy = data.aws_iam_policy_document.signal_writer_execution_secrets.json
}

resource "aws_iam_role" "signal_writer_task" {
  name               = "${local.name_prefix}-signal-writer-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = local.common_tags
}

resource "aws_secretsmanager_secret" "database_url" {
  name                    = local.database_url_secret_name
  description             = "DATABASE_URL for the Arbiter API service."
  recovery_window_in_days = 0

  tags = local.common_tags
}

resource "aws_ecs_task_definition" "api" {
  family                   = "${local.name_prefix}-api"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(var.api_cpu)
  memory                   = tostring(var.api_memory)
  execution_role_arn       = aws_iam_role.api_execution.arn
  task_role_arn            = aws_iam_role.api_task.arn

  container_definitions = jsonencode([
    {
      name      = local.api_container_name
      image     = var.api_image_uri
      essential = true

      portMappings = [
        {
          containerPort = var.api_container_port
          hostPort      = var.api_container_port
          protocol      = "tcp"
        }
      ]

      environment = concat(
        [
          {
            name  = "API_ADDRESS"
            value = ":${var.api_container_port}"
          }
        ],
        var.use_database_url_secret ? [] : [
          {
            name  = "DATABASE_URL"
            value = var.database_url
          }
        ]
      )

      secrets = var.use_database_url_secret ? [
        {
          name      = "DATABASE_URL"
          valueFrom = aws_secretsmanager_secret.database_url.arn
        }
      ] : []

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.api.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = local.common_tags
}

resource "aws_ecs_service" "api" {
  name                   = "${local.name_prefix}-api"
  cluster                = aws_ecs_cluster.main.id
  task_definition        = aws_ecs_task_definition.api.arn
  desired_count          = var.api_desired_count
  launch_type            = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets          = var.public_subnet_ids
    security_groups  = [aws_security_group.api_service.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = local.api_container_name
    container_port   = var.api_container_port
  }

  health_check_grace_period_seconds = 60

  depends_on = [
    aws_lb_listener.http,
    aws_iam_role_policy_attachment.api_execution_ecs,
    aws_iam_role_policy.api_execution_secrets,
    aws_vpc_security_group_ingress_rule.postgres_from_api,
  ]

  tags = local.common_tags
}

resource "aws_ecs_task_definition" "signal_writer" {
  family                   = "${local.name_prefix}-signal-writer"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(var.signal_writer_cpu)
  memory                   = tostring(var.signal_writer_memory)
  execution_role_arn       = aws_iam_role.signal_writer_execution.arn
  task_role_arn            = aws_iam_role.signal_writer_task.arn

  container_definitions = jsonencode([
    {
      name      = local.signal_writer_name
      image     = var.signal_writer_image_uri
      essential = true

      environment = [
        {
          name  = "KAFKA_BROKERS"
          value = var.kafka_brokers
        },
        {
          name  = "SIGNALS_TOPIC"
          value = var.signals_topic
        },
        {
          name  = "KAFKA_GROUP_ID"
          value = var.signal_writer_group_id
        },
        {
          name  = "KAFKA_START_OFFSET"
          value = var.signal_writer_start_offset
        }
      ]

      secrets = [
        {
          name      = "DATABASE_URL"
          valueFrom = aws_secretsmanager_secret.database_url.arn
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.signal_writer.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = local.common_tags
}

resource "aws_ecs_service" "signal_writer" {
  name                   = "${local.name_prefix}-signal-writer"
  cluster                = aws_ecs_cluster.main.id
  task_definition        = aws_ecs_task_definition.signal_writer.arn
  desired_count          = var.signal_writer_desired_count
  launch_type            = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets          = var.public_subnet_ids
    security_groups  = [aws_security_group.signal_writer.id]
    assign_public_ip = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.signal_writer_execution_ecs,
    aws_iam_role_policy.signal_writer_execution_secrets,
    aws_vpc_security_group_ingress_rule.postgres_from_signal_writer,
    aws_vpc_security_group_ingress_rule.kafka_from_signal_writer,
  ]

  tags = local.common_tags
}
