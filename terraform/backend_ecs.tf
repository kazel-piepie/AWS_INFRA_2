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
