# ECS Fargate cluster, task definition, and service for the backend.

resource "aws_ecs_cluster" "backend" {
  name = "${local.backend_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = {
    Name = "${local.backend_name}-cluster"
  }
}

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/${local.backend_name}"
  retention_in_days = 14

  tags = {
    Name = "${local.backend_name}-logs"
  }
}

# --- IAM roles for the task (execution + task role) ---

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Execution role: pulls the image and injects secrets into the container.
resource "aws_iam_role" "backend_task_exec" {
  name               = "${local.backend_name}-task-exec-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json

  tags = {
    Name = "${local.backend_name}-task-exec-role"
  }
}

resource "aws_iam_role_policy_attachment" "backend_task_exec_managed" {
  role       = aws_iam_role.backend_task_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Execution role may read only the two RORR secrets (exact ARNs, no wildcard).
data "aws_iam_policy_document" "backend_task_exec_secrets" {
  statement {
    sid    = "ReadRorrSecretsForInjection"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [
      data.aws_secretsmanager_secret.rorr.arn,
      data.aws_secretsmanager_secret.rorr_infra.arn,
    ]
  }
}

resource "aws_iam_role_policy" "backend_task_exec_secrets" {
  name   = "${local.backend_name}-task-exec-secrets"
  role   = aws_iam_role.backend_task_exec.id
  policy = data.aws_iam_policy_document.backend_task_exec_secrets.json
}

# Task role: runtime identity for the application container.
resource "aws_iam_role" "backend_task" {
  name               = "${local.backend_name}-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json

  tags = {
    Name = "${local.backend_name}-task-role"
  }
}

# Runtime read of only the ai/rorr secret (exact ARN, no wildcard).
data "aws_iam_policy_document" "backend_task_secrets" {
  statement {
    sid    = "ReadRorrSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [data.aws_secretsmanager_secret.rorr.arn]
  }
}

resource "aws_iam_role_policy" "backend_task_secrets" {
  name   = "${local.backend_name}-task-secrets"
  role   = aws_iam_role.backend_task.id
  policy = data.aws_iam_policy_document.backend_task_secrets.json
}

# --- Task definition ---

resource "aws_ecs_task_definition" "backend" {
  family                   = "${local.backend_name}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.backend_task_cpu
  memory                   = var.backend_task_memory
  execution_role_arn       = aws_iam_role.backend_task_exec.arn
  task_role_arn            = aws_iam_role.backend_task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = var.backend_container_name
      image     = "${aws_ecr_repository.backend.repository_url}:${var.backend_image_tag}"
      essential = true

      portMappings = [
        {
          containerPort = var.backend_container_port
          protocol      = "tcp"
        }
      ]

      # Inject full secret ARNs (per infra rule: ARN only, never ARN#key).
      secrets = [
        {
          name      = "RORR_SECRET_JSON"
          valueFrom = data.aws_secretsmanager_secret.rorr.arn
        },
        {
          name      = "RORR_INFRA_SECRET_JSON"
          valueFrom = data.aws_secretsmanager_secret.rorr_infra.arn
        },
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
    Name = "${local.backend_name}-task"
  }
}

# --- Service ---

resource "aws_ecs_service" "backend" {
  name            = "${local.backend_name}-service"
  cluster         = aws_ecs_cluster.backend.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = var.backend_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.backend_task.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = var.backend_container_name
    container_port   = var.backend_container_port
  }

  depends_on = [aws_lb_listener.backend_https]

  # CI/CD rolls out new task definitions and may scale the service; let it own
  # those fields after the initial create.
  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  tags = {
    Name = "${local.backend_name}-service"
  }
}
