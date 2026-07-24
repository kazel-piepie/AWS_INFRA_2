locals {
  backend_name = "${local.name_prefix}-backend"
}

# Security group for the backend ECS Fargate tasks. Inbound only from the ALB
# on the container port; outbound to the DB / secrets / ECR via NAT.
resource "aws_security_group" "backend_ecs" {
  name        = "${local.name_prefix}-backend-ecs-sg"
  description = "RORR backend ECS Fargate tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "App traffic from backend ALB"
    from_port       = var.backend_container_port
    to_port         = var.backend_container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.backend_alb.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-backend-ecs-sg"
  }
}

# ECS cluster for the backend service.
resource "aws_ecs_cluster" "backend" {
  name = "${local.name_prefix}-backend-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name      = "${local.name_prefix}-backend-cluster"
    Component = "backend"
  }
}

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/${local.name_prefix}-backend"
  retention_in_days = 14

  tags = {
    Name      = "${local.name_prefix}-backend"
    Component = "backend"
  }
}

# ---------------------------------------------------------------------------
# Task execution role (pulls image from ECR, writes logs, injects secrets).
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "backend_ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backend_task_execution" {
  name               = "${local.name_prefix}-backend-task-exec-role"
  assume_role_policy = data.aws_iam_policy_document.backend_ecs_assume.json

  tags = {
    Name      = "${local.name_prefix}-backend-task-exec-role"
    Component = "backend"
  }
}

resource "aws_iam_role_policy_attachment" "backend_task_execution_managed" {
  role       = aws_iam_role.backend_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Allow the execution role to read the RORR secret for secret injection.
resource "aws_iam_role_policy_attachment" "backend_task_execution_secret" {
  role       = aws_iam_role.backend_task_execution.name
  policy_arn = aws_iam_policy.rorr_secret_read.arn
}

# AmazonECSTaskExecutionRolePolicy grants CreateLogStream / PutLogEvents but not
# CreateLogGroup. The log group is pre-created (aws_cloudwatch_log_group.backend),
# but grant CreateLogGroup as a safeguard against deletion / awslogs-create-group.
data "aws_iam_policy_document" "backend_logs_create" {
  statement {
    sid       = "CreateBackendLogGroup"
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup"]
    resources = ["arn:aws:logs:${local.region_id}:${local.account_id}:log-group:/ecs/${local.name_prefix}-backend:*"]
  }
}

resource "aws_iam_role_policy" "backend_logs_create" {
  name   = "${local.name_prefix}-backend-logs-create"
  role   = aws_iam_role.backend_task_execution.id
  policy = data.aws_iam_policy_document.backend_logs_create.json
}

# ---------------------------------------------------------------------------
# Task role (application runtime permissions).
# ---------------------------------------------------------------------------
resource "aws_iam_role" "backend_task" {
  name               = "${local.name_prefix}-backend-task-role"
  assume_role_policy = data.aws_iam_policy_document.backend_ecs_assume.json

  tags = {
    Name      = "${local.name_prefix}-backend-task-role"
    Component = "backend"
  }
}

# Backend runtime reads the RORR secret (DB / Redis / MSK credentials).
resource "aws_iam_role_policy_attachment" "backend_task_secret" {
  role       = aws_iam_role.backend_task.name
  policy_arn = aws_iam_policy.rorr_secret_read.arn
}

# Backend runtime sends transactional email via SES from any verified identity
# (the rorr.club domain plus individually verified email addresses).
data "aws_iam_policy_document" "backend_ses_send" {
  statement {
    sid    = "SendRorrClubEmail"
    effect = "Allow"
    actions = [
      "ses:SendEmail",
      "ses:SendRawEmail",
      "sesv2:SendEmail",
    ]
    resources = ["arn:aws:ses:${local.region_id}:${local.account_id}:identity/*"]
  }
}

resource "aws_iam_policy" "backend_ses_send" {
  name        = "${local.name_prefix}-backend-ses-send"
  description = "Send email via SES from any verified identity"
  policy      = data.aws_iam_policy_document.backend_ses_send.json
}

resource "aws_iam_role_policy_attachment" "backend_task_ses_send" {
  role       = aws_iam_role.backend_task.name
  policy_arn = aws_iam_policy.backend_ses_send.arn
}

# ECS Exec (enable_execute_command) opens an SSM session channel into the
# running container for debugging / connectivity testing. The SSM messages
# API actions do not support resource-level permissions, so Resource must be
# "*". Granted on the task role (the identity the SSM agent runs under).
data "aws_iam_policy_document" "backend_ecs_exec" {
  statement {
    sid    = "AllowEcsExecSsmMessages"
    effect = "Allow"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "backend_ecs_exec" {
  name   = "${local.name_prefix}-backend-ecs-exec"
  role   = aws_iam_role.backend_task.id
  policy = data.aws_iam_policy_document.backend_ecs_exec.json
}

# backend-service consumes rorr-lol-object-events / rorr-lol-object-events-dlq
# over SASL/IAM. Consume-only: Connect on the cluster, ReadData/DescribeTopic
# scoped to exactly the two object-events topics (no wildcard, no
# CreateTopic/WriteData), and DescribeGroup/AlterGroup on any consumer group so
# the app picks its own group name (same group-wildcard pattern as the other
# consumer modules). Mirrors ai-service's ai-msk-consume inline policy.
data "aws_iam_policy_document" "backend_task_msk" {
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

resource "aws_iam_role_policy" "backend_task_msk" {
  name   = "${local.name_prefix}-backend-msk-consume"
  role   = aws_iam_role.backend_task.id
  policy = data.aws_iam_policy_document.backend_task_msk.json
}

# ---------------------------------------------------------------------------
# Task definition.
# ---------------------------------------------------------------------------
resource "aws_ecs_task_definition" "backend" {
  family                   = "${local.name_prefix}-backend-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.backend_cpu
  memory                   = var.backend_memory
  execution_role_arn       = aws_iam_role.backend_task_execution.arn
  task_role_arn            = aws_iam_role.backend_task.arn

  container_definitions = jsonencode([
    {
      name      = "backend"
      image     = "${aws_ecr_repository.backend.repository_url}:latest"
      essential = true

      portMappings = [
        {
          containerPort = var.backend_container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "ENV", value = var.env },
        { name = "AWS_REGION", value = var.region }
      ]

      # Full secret ARN in valueFrom (never ARN#key) per infra rules.
      secrets = [
        { name = "RORR_SECRET_JSON", valueFrom = data.aws_secretsmanager_secret.rorr.arn }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.backend.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "backend"
        }
      }
    }
  ])

  tags = {
    Name      = "${local.name_prefix}-backend-task"
    Component = "backend"
  }
}

# ---------------------------------------------------------------------------
# Service.
# ---------------------------------------------------------------------------
resource "aws_ecs_service" "backend" {
  name            = "${local.name_prefix}-backend-service"
  cluster         = aws_ecs_cluster.backend.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = var.backend_desired_count
  launch_type     = "FARGATE"

  # Allow ECS Exec (aws ecs execute-command) into the running container for
  # debugging / connectivity testing. Takes effect on the next deployment.
  enable_execute_command = true

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.backend_ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "backend"
    container_port   = var.backend_container_port
  }

  # Client-side Service Connect: join the private namespace so the backend can
  # reach the ai-service at the stable name "ai-service" (no server block here;
  # the backend is a client, it does not advertise itself).
  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_private_dns_namespace.rorr_internal.arn
  }

  # CI/CD updates the image/task definition out of band; ignore those drifts.
  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  depends_on = [aws_lb_listener.backend_https]

  tags = {
    Name      = "${local.name_prefix}-backend-service"
    Component = "backend"
  }
}
