locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  api_container_name       = "api"
  signal_writer_name       = "signal-writer"
  detector_name            = "detector"
  normalizer_coinbase_name = "normalizer-coinbase"
  normalizer_kraken_name   = "normalizer-kraken"
  ingestor_coinbase_name   = "ingestor-coinbase"
  ingestor_kraken_name     = "ingestor-kraken"
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

resource "aws_security_group" "detector" {
  name        = "${local.name_prefix}-detector"
  description = "Security group for the detector ECS tasks."
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound traffic."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-detector-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "kafka_from_detector" {
  count = trimspace(var.kafka_security_group_id) == "" ? 0 : 1

  security_group_id            = var.kafka_security_group_id
  referenced_security_group_id = aws_security_group.detector.id
  description                  = "Allow Kafka access from the detector ECS tasks."
  from_port                    = 9092
  to_port                      = 9092
  ip_protocol                  = "tcp"
}

resource "aws_security_group" "normalizer_coinbase" {
  name        = "${local.name_prefix}-normalizer-coinbase"
  description = "Security group for the Coinbase normalizer ECS tasks."
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound traffic."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-normalizer-coinbase-sg"
  })
}

resource "aws_security_group" "normalizer_kraken" {
  name        = "${local.name_prefix}-normalizer-kraken"
  description = "Security group for the Kraken normalizer ECS tasks."
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound traffic."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-normalizer-kraken-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "kafka_from_normalizer_coinbase" {
  count = trimspace(var.kafka_security_group_id) == "" ? 0 : 1

  security_group_id            = var.kafka_security_group_id
  referenced_security_group_id = aws_security_group.normalizer_coinbase.id
  description                  = "Allow Kafka access from the Coinbase normalizer ECS tasks."
  from_port                    = 9092
  to_port                      = 9092
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "kafka_from_normalizer_kraken" {
  count = trimspace(var.kafka_security_group_id) == "" ? 0 : 1

  security_group_id            = var.kafka_security_group_id
  referenced_security_group_id = aws_security_group.normalizer_kraken.id
  description                  = "Allow Kafka access from the Kraken normalizer ECS tasks."
  from_port                    = 9092
  to_port                      = 9092
  ip_protocol                  = "tcp"
}

resource "aws_security_group" "ingestor_coinbase" {
  name        = "${local.name_prefix}-ingestor-coinbase"
  description = "Security group for the Coinbase ingestor ECS tasks."
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound traffic."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ingestor-coinbase-sg"
  })
}

resource "aws_security_group" "ingestor_kraken" {
  name        = "${local.name_prefix}-ingestor-kraken"
  description = "Security group for the Kraken ingestor ECS tasks."
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound traffic."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ingestor-kraken-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "kafka_from_ingestor_coinbase" {
  count = trimspace(var.kafka_security_group_id) == "" ? 0 : 1

  security_group_id            = var.kafka_security_group_id
  referenced_security_group_id = aws_security_group.ingestor_coinbase.id
  description                  = "Allow Kafka access from the Coinbase ingestor ECS tasks."
  from_port                    = 9092
  to_port                      = 9092
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "kafka_from_ingestor_kraken" {
  count = trimspace(var.kafka_security_group_id) == "" ? 0 : 1

  security_group_id            = var.kafka_security_group_id
  referenced_security_group_id = aws_security_group.ingestor_kraken.id
  description                  = "Allow Kafka access from the Kraken ingestor ECS tasks."
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

resource "aws_cloudwatch_log_group" "detector" {
  name              = "/aws/ecs/${local.name_prefix}/detector"
  retention_in_days = 14

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "normalizer_coinbase" {
  name              = "/aws/ecs/${local.name_prefix}/normalizer-coinbase"
  retention_in_days = 14

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "normalizer_kraken" {
  name              = "/aws/ecs/${local.name_prefix}/normalizer-kraken"
  retention_in_days = 14

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "ingestor_coinbase" {
  name              = "/aws/ecs/${local.name_prefix}/ingestor-coinbase"
  retention_in_days = 14

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "ingestor_kraken" {
  name              = "/aws/ecs/${local.name_prefix}/ingestor-kraken"
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

resource "aws_iam_role" "detector_execution" {
  name               = "${local.name_prefix}-detector-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "detector_execution_ecs" {
  role       = aws_iam_role.detector_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "detector_task" {
  name               = "${local.name_prefix}-detector-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role" "normalizer_execution" {
  name               = "${local.name_prefix}-normalizer-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "normalizer_execution_ecs" {
  role       = aws_iam_role.normalizer_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "normalizer_task" {
  name               = "${local.name_prefix}-normalizer-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role" "ingestor_execution" {
  name               = "${local.name_prefix}-ingestor-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ingestor_execution_ecs" {
  role       = aws_iam_role.ingestor_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ingestor_task" {
  name               = "${local.name_prefix}-ingestor-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = local.common_tags
}

resource "aws_secretsmanager_secret" "database_url" {
  name                    = local.database_url_secret_name
  description             = "DATABASE_URL for the Arbiter API service."
  recovery_window_in_days = 0

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "database_url" {
  secret_id     = aws_secretsmanager_secret.database_url.id
  secret_string = var.database_url
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

resource "aws_ecs_task_definition" "detector" {
  family                   = "${local.name_prefix}-detector"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(var.detector_cpu)
  memory                   = tostring(var.detector_memory)
  execution_role_arn       = aws_iam_role.detector_execution.arn
  task_role_arn            = aws_iam_role.detector_task.arn

  container_definitions = jsonencode([
    {
      name      = local.detector_name
      image     = var.detector_image_uri
      essential = true

      environment = [
        {
          name  = "KAFKA_BROKERS"
          value = var.kafka_brokers
        },
        {
          name  = "NORMALIZED_TICKS_TOPIC"
          value = var.normalized_ticks_topic
        },
        {
          name  = "SIGNALS_TOPIC"
          value = var.signals_topic
        },
        {
          name  = "KAFKA_GROUP_ID"
          value = var.detector_group_id
        },
        {
          name  = "KAFKA_START_OFFSET"
          value = var.detector_start_offset
        },
        {
          name  = "MIN_SIGNAL_PROFIT"
          value = tostring(var.detector_min_signal_profit)
        },
        {
          name  = "FEE_BPS"
          value = tostring(var.detector_fee_bps)
        },
        {
          name  = "MAX_QUOTE_AGE_MS"
          value = tostring(var.detector_max_quote_age_ms)
        },
        {
          name  = "MAX_QUOTE_GAP_MS"
          value = tostring(var.detector_max_quote_gap_ms)
        },
        {
          name  = "MIN_SIGNAL_INTERVAL_MS"
          value = tostring(var.detector_min_signal_interval_ms)
        },
        {
          name  = "DETECTOR_DEBUG"
          value = tostring(var.detector_debug)
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.detector.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = local.common_tags
}

resource "aws_ecs_service" "detector" {
  name                   = "${local.name_prefix}-detector"
  cluster                = aws_ecs_cluster.main.id
  task_definition        = aws_ecs_task_definition.detector.arn
  desired_count          = var.detector_desired_count
  launch_type            = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets          = var.public_subnet_ids
    security_groups  = [aws_security_group.detector.id]
    assign_public_ip = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.detector_execution_ecs,
    aws_vpc_security_group_ingress_rule.kafka_from_detector,
  ]

  tags = local.common_tags
}

resource "aws_ecs_task_definition" "normalizer_coinbase" {
  family                   = "${local.name_prefix}-normalizer-coinbase"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(var.normalizer_cpu)
  memory                   = tostring(var.normalizer_memory)
  execution_role_arn       = aws_iam_role.normalizer_execution.arn
  task_role_arn            = aws_iam_role.normalizer_task.arn

  container_definitions = jsonencode([
    {
      name      = local.normalizer_coinbase_name
      image     = var.normalizer_image_uri
      essential = true

      environment = [
        {
          name  = "KAFKA_BROKERS"
          value = var.kafka_brokers
        },
        {
          name  = "RAW_TICKS_TOPIC"
          value = var.raw_ticks_coinbase_topic
        },
        {
          name  = "NORMALIZED_TICKS_TOPIC"
          value = var.normalized_ticks_topic
        },
        {
          name  = "KAFKA_GROUP_ID"
          value = var.normalizer_coinbase_group_id
        },
        {
          name  = "KAFKA_START_OFFSET"
          value = var.normalizer_start_offset
        },
        {
          name  = "NORMALIZER_DEBUG"
          value = tostring(var.normalizer_debug)
        },
        {
          name  = "NORMALIZER_LOG_EVERY_N"
          value = tostring(var.normalizer_log_every_n)
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.normalizer_coinbase.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = local.common_tags
}

resource "aws_ecs_task_definition" "normalizer_kraken" {
  family                   = "${local.name_prefix}-normalizer-kraken"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(var.normalizer_cpu)
  memory                   = tostring(var.normalizer_memory)
  execution_role_arn       = aws_iam_role.normalizer_execution.arn
  task_role_arn            = aws_iam_role.normalizer_task.arn

  container_definitions = jsonencode([
    {
      name      = local.normalizer_kraken_name
      image     = var.normalizer_image_uri
      essential = true

      environment = [
        {
          name  = "KAFKA_BROKERS"
          value = var.kafka_brokers
        },
        {
          name  = "RAW_TICKS_TOPIC"
          value = var.raw_ticks_kraken_topic
        },
        {
          name  = "NORMALIZED_TICKS_TOPIC"
          value = var.normalized_ticks_topic
        },
        {
          name  = "KAFKA_GROUP_ID"
          value = var.normalizer_kraken_group_id
        },
        {
          name  = "KAFKA_START_OFFSET"
          value = var.normalizer_start_offset
        },
        {
          name  = "NORMALIZER_DEBUG"
          value = tostring(var.normalizer_debug)
        },
        {
          name  = "NORMALIZER_LOG_EVERY_N"
          value = tostring(var.normalizer_log_every_n)
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.normalizer_kraken.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = local.common_tags
}

resource "aws_ecs_service" "normalizer_coinbase" {
  name                   = "${local.name_prefix}-normalizer-coinbase"
  cluster                = aws_ecs_cluster.main.id
  task_definition        = aws_ecs_task_definition.normalizer_coinbase.arn
  desired_count          = var.normalizer_coinbase_desired_count
  launch_type            = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets          = var.public_subnet_ids
    security_groups  = [aws_security_group.normalizer_coinbase.id]
    assign_public_ip = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.normalizer_execution_ecs,
    aws_vpc_security_group_ingress_rule.kafka_from_normalizer_coinbase,
  ]

  tags = local.common_tags
}

resource "aws_ecs_service" "normalizer_kraken" {
  name                   = "${local.name_prefix}-normalizer-kraken"
  cluster                = aws_ecs_cluster.main.id
  task_definition        = aws_ecs_task_definition.normalizer_kraken.arn
  desired_count          = var.normalizer_kraken_desired_count
  launch_type            = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets          = var.public_subnet_ids
    security_groups  = [aws_security_group.normalizer_kraken.id]
    assign_public_ip = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.normalizer_execution_ecs,
    aws_vpc_security_group_ingress_rule.kafka_from_normalizer_kraken,
  ]

  tags = local.common_tags
}

resource "aws_ecs_task_definition" "ingestor_coinbase" {
  family                   = "${local.name_prefix}-ingestor-coinbase"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(var.ingestor_cpu)
  memory                   = tostring(var.ingestor_memory)
  execution_role_arn       = aws_iam_role.ingestor_execution.arn
  task_role_arn            = aws_iam_role.ingestor_task.arn

  container_definitions = jsonencode([
    {
      name      = local.ingestor_coinbase_name
      image     = var.ingestor_coinbase_image_uri
      essential = true

      environment = [
        {
          name  = "KAFKA_BROKERS"
          value = var.kafka_brokers
        },
        {
          name  = "RAW_TICKS_TOPIC"
          value = var.raw_ticks_coinbase_topic
        },
        {
          name  = "COINBASE_PRODUCT_ID"
          value = var.coinbase_product_id
        },
        {
          name  = "COINBASE_WS_URL"
          value = var.coinbase_ws_url
        },
        {
          name  = "INGESTOR_DEBUG"
          value = tostring(var.ingestor_debug)
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ingestor_coinbase.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = local.common_tags
}

resource "aws_ecs_task_definition" "ingestor_kraken" {
  family                   = "${local.name_prefix}-ingestor-kraken"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(var.ingestor_cpu)
  memory                   = tostring(var.ingestor_memory)
  execution_role_arn       = aws_iam_role.ingestor_execution.arn
  task_role_arn            = aws_iam_role.ingestor_task.arn

  container_definitions = jsonencode([
    {
      name      = local.ingestor_kraken_name
      image     = var.ingestor_kraken_image_uri
      essential = true

      environment = [
        {
          name  = "KAFKA_BROKERS"
          value = var.kafka_brokers
        },
        {
          name  = "RAW_TICKS_TOPIC"
          value = var.raw_ticks_kraken_topic
        },
        {
          name  = "KRAKEN_SYMBOL"
          value = var.kraken_symbol
        },
        {
          name  = "KRAKEN_WS_URL"
          value = var.kraken_ws_url
        },
        {
          name  = "INGESTOR_DEBUG"
          value = tostring(var.ingestor_debug)
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ingestor_kraken.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = local.common_tags
}

resource "aws_ecs_service" "ingestor_coinbase" {
  name                   = "${local.name_prefix}-ingestor-coinbase"
  cluster                = aws_ecs_cluster.main.id
  task_definition        = aws_ecs_task_definition.ingestor_coinbase.arn
  desired_count          = var.ingestor_coinbase_desired_count
  launch_type            = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets          = var.public_subnet_ids
    security_groups  = [aws_security_group.ingestor_coinbase.id]
    assign_public_ip = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.ingestor_execution_ecs,
    aws_vpc_security_group_ingress_rule.kafka_from_ingestor_coinbase,
  ]

  tags = local.common_tags
}

resource "aws_ecs_service" "ingestor_kraken" {
  name                   = "${local.name_prefix}-ingestor-kraken"
  cluster                = aws_ecs_cluster.main.id
  task_definition        = aws_ecs_task_definition.ingestor_kraken.arn
  desired_count          = var.ingestor_kraken_desired_count
  launch_type            = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets          = var.public_subnet_ids
    security_groups  = [aws_security_group.ingestor_kraken.id]
    assign_public_ip = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.ingestor_execution_ecs,
    aws_vpc_security_group_ingress_rule.kafka_from_ingestor_kraken,
  ]

  tags = local.common_tags
}
