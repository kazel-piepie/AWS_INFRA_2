# ---------------------------------------------------------------------------
# ai-service (LoL AI companion): a Fargate service running on the EXISTING
# backend cluster (ai-rorr-develop-backend-cluster). No new cluster is created.
# Dedicated task/exec roles (not shared with backend). Reached in-cluster by
# backend-service over ECS Service Connect via a stable internal DNS name.
# ---------------------------------------------------------------------------
locals {
  ai_name = "${local.name_prefix}-ai"
}

# Security group for the ai-service Fargate tasks. Inbound ONLY from the backend
# ECS tasks on the container port; outbound to DB / Redis / secrets / ECR / etc.
resource "aws_security_group" "ai_ecs" {
  name        = "${local.name_prefix}-ai-ecs-sg"
  description = "RORR ai-service ECS Fargate tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "App traffic from backend ECS tasks"
    from_port       = var.ai_container_port
    to_port         = var.ai_container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.backend_ecs.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-ai-ecs-sg"
  }
}

resource "aws_cloudwatch_log_group" "ai" {
  name              = "/ecs/${local.name_prefix}-ai"
  retention_in_days = 14

  tags = {
    Name      = "/ecs/${local.name_prefix}-ai"
    Component = "ai-service"
  }
}

# ---------------------------------------------------------------------------
# Cloud Map namespace for ECS Service Connect. None exists in this VPC yet, so
# create a private DNS namespace shared by cluster services for stable in-cluster
# DNS. ai-service registers here; backend-service resolves it as a client.
# ---------------------------------------------------------------------------
resource "aws_service_discovery_private_dns_namespace" "rorr_internal" {
  name        = "${local.name_prefix}.internal"
  description = "Private DNS namespace for RORR ECS Service Connect"
  vpc         = aws_vpc.main.id

  tags = {
    Name      = "${local.name_prefix}.internal"
    Component = "ai-service"
  }
}

# ---------------------------------------------------------------------------
# Dedicated task execution role (pulls image from ECR, writes logs, injects
# secrets). Not shared with the backend roles.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ai_ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ai_task_execution" {
  name               = "${local.name_prefix}-ai-task-exec-role"
  assume_role_policy = data.aws_iam_policy_document.ai_ecs_assume.json

  tags = {
    Name      = "${local.name_prefix}-ai-task-exec-role"
    Component = "ai-service"
  }
}

resource "aws_iam_role_policy_attachment" "ai_task_execution_managed" {
  role       = aws_iam_role.ai_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Reuse the existing least-privilege ai/rorr secret-read policy (exact ARN,
# no wildcard). The execution role needs it to resolve the per-key secrets.
resource "aws_iam_role_policy_attachment" "ai_task_execution_secret" {
  role       = aws_iam_role.ai_task_execution.name
  policy_arn = aws_iam_policy.rorr_secret_read.arn
}

# AmazonECSTaskExecutionRolePolicy grants CreateLogStream / PutLogEvents but not
# CreateLogGroup. The log group is pre-created; grant CreateLogGroup as a
# safeguard against deletion / awslogs-create-group.
data "aws_iam_policy_document" "ai_logs_create" {
  statement {
    sid       = "CreateAiLogGroup"
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup"]
    resources = ["arn:aws:logs:${local.region_id}:${local.account_id}:log-group:/ecs/${local.name_prefix}-ai:*"]
  }
}

resource "aws_iam_role_policy" "ai_logs_create" {
  name   = "${local.name_prefix}-ai-logs-create"
  role   = aws_iam_role.ai_task_execution.id
  policy = data.aws_iam_policy_document.ai_logs_create.json
}

# ---------------------------------------------------------------------------
# Dedicated task role (application runtime permissions). Not shared with backend.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "ai_task" {
  name               = "${local.name_prefix}-ai-task-role"
  assume_role_policy = data.aws_iam_policy_document.ai_ecs_assume.json

  tags = {
    Name      = "${local.name_prefix}-ai-task-role"
    Component = "ai-service"
  }
}

# ai-service runtime reads the RORR secret (DB / Redis credentials). Reuses the
# existing ai-rorr-develop-secret-read managed policy (single-ARN scoped).
resource "aws_iam_role_policy_attachment" "ai_task_secret" {
  role       = aws_iam_role.ai_task.name
  policy_arn = aws_iam_policy.rorr_secret_read.arn
}

# ai-service consumes rorr-lol-object-events / rorr-lol-object-events-dlq over
# SASL/IAM. Consume-only: Connect on the cluster, ReadData/DescribeTopic scoped
# to exactly the two object-events topics (no wildcard, no CreateTopic/WriteData),
# and DescribeGroup/AlterGroup on any consumer group so the app picks its own
# group name (same group-wildcard pattern as the other consumer modules).
data "aws_iam_policy_document" "ai_task_msk" {
  statement {
    sid       = "MskConnect"
    effect    = "Allow"
    actions   = ["kafka-cluster:Connect"]
    resources = [aws_msk_cluster.main.arn]
  }
  statement {
    sid    = "TopicConsume"
    effect = "Allow"
    actions = [
      "kafka-cluster:ReadData",
      "kafka-cluster:DescribeTopic",
    ]
    resources = [
      "${local.msk_topic_arn_prefix}/rorr-lol-object-events",
      "${local.msk_topic_arn_prefix}/rorr-lol-object-events-dlq",
    ]
  }
  statement {
    sid       = "ConsumerGroup"
    effect    = "Allow"
    actions   = ["kafka-cluster:DescribeGroup", "kafka-cluster:AlterGroup"]
    resources = ["${local.msk_group_arn_prefix}/*"]
  }
}

resource "aws_iam_role_policy" "ai_task_msk" {
  name   = "${local.name_prefix}-ai-msk-consume"
  role   = aws_iam_role.ai_task.id
  policy = data.aws_iam_policy_document.ai_task_msk.json
}

# ---------------------------------------------------------------------------
# Bedrock invoke permission for Claude Haiku via the cross-region inference
# profile us.anthropic.claude-haiku-4-5-20251001-v1:0. The profile routes
# through us-east-1 / us-east-2 / us-west-2, so the underlying foundation
# models in all three regions must be allowed alongside the profile ARN.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ai_task_bedrock" {
  statement {
    sid    = "BedrockInvokeHaiku"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
    ]
    resources = [
      "arn:aws:bedrock:us-east-1:161327178737:inference-profile/us.anthropic.claude-haiku-4-5-20251001-v1:0",
      "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-haiku-4-5-20251001-v1:0",
      "arn:aws:bedrock:us-east-2::foundation-model/anthropic.claude-haiku-4-5-20251001-v1:0",
      "arn:aws:bedrock:us-west-2::foundation-model/anthropic.claude-haiku-4-5-20251001-v1:0",
    ]
  }
}

resource "aws_iam_role_policy" "ai_task_bedrock" {
  name   = "${local.name_prefix}-ai-bedrock-invoke"
  role   = aws_iam_role.ai_task.id
  policy = data.aws_iam_policy_document.ai_task_bedrock.json
}

# ---------------------------------------------------------------------------
# Task definition. Develop sizing: 256 CPU / 512 MiB (same minimum as backend).
# DB / Redis credentials are injected as individual environment variables from
# per-key references into ai/rorr/{env}, matching the live backend task revision.
# ---------------------------------------------------------------------------
resource "aws_ecs_task_definition" "ai" {
  family                   = "${local.name_prefix}-ai-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.ai_cpu
  memory                   = var.ai_memory
  execution_role_arn       = aws_iam_role.ai_task_execution.arn
  task_role_arn            = aws_iam_role.ai_task.arn

  container_definitions = jsonencode([
    {
      name      = "ai"
      image     = "${aws_ecr_repository.ai.repository_url}:latest"
      essential = true

      # Named port mapping is required for the Service Connect port_name binding.
      portMappings = [
        {
          name          = "ai"
          containerPort = var.ai_container_port
          protocol      = "tcp"
          appProtocol   = "http"
        }
      ]

      environment = [
        { name = "ENV", value = var.env },
        { name = "AWS_REGION", value = var.region }
      ]

      # Per-key injection from ai/rorr/{env} (ARN:jsonkey:: format), matching the
      # live ai-rorr-develop-backend-task revision.
      secrets = [
        { name = "DB_HOST", valueFrom = "${data.aws_secretsmanager_secret.rorr.arn}:db_host::" },
        { name = "DB_PORT", valueFrom = "${data.aws_secretsmanager_secret.rorr.arn}:db_port::" },
        { name = "DB_USER", valueFrom = "${data.aws_secretsmanager_secret.rorr.arn}:db_user::" },
        { name = "DB_PASSWORD", valueFrom = "${data.aws_secretsmanager_secret.rorr.arn}:db_password::" },
        { name = "REDIS_HOST", valueFrom = "${data.aws_secretsmanager_secret.rorr.arn}:redis_host::" },
        { name = "REDIS_PORT", valueFrom = "${data.aws_secretsmanager_secret.rorr.arn}:redis_port::" },
        { name = "REDIS_PASSWORD", valueFrom = "${data.aws_secretsmanager_secret.rorr.arn}:redis_password::" },
        { name = "MSK_BOOTSTRAP_SERVERS", valueFrom = "${data.aws_secretsmanager_secret.rorr.arn}:msk_bootstrap_servers::" },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ai.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ai"
        }
      }
    }
  ])

  tags = {
    Name      = "${local.name_prefix}-ai-task"
    Component = "ai-service"
  }
}

# ---------------------------------------------------------------------------
# Service on the existing backend cluster. Service Connect advertises the task
# under the stable name "ai-service" in the private namespace so backend-service
# can reach it at http://ai-service:<port> without tracking task IPs.
# CI/CD rolls image/task-definition out of band, so those drifts are ignored.
# ---------------------------------------------------------------------------
resource "aws_ecs_service" "ai" {
  name            = "${local.name_prefix}-ai-service"
  cluster         = aws_ecs_cluster.backend.id
  task_definition = aws_ecs_task_definition.ai.arn
  desired_count   = var.ai_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ai_ecs.id]
    assign_public_ip = false
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_private_dns_namespace.rorr_internal.arn

    service {
      port_name      = "ai"
      discovery_name = "ai-service"

      client_alias {
        port     = var.ai_container_port
        dns_name = "ai-service"
      }
    }

    log_configuration {
      log_driver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ai.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "service-connect"
      }
    }
  }

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  tags = {
    Name      = "${local.name_prefix}-ai-service"
    Component = "ai-service"
  }
}
