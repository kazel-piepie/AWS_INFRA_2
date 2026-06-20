# ---------------------------------------------------------------------------
# MCP datacenter Fargate service running on the shared backend cluster.
# This service provides datacenter data to the MCP server.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "datacenter" {
  name              = "/ecs/ai-mcp-dev-datacenter"
  retention_in_days = 7

  tags = {
    Name      = "/ecs/ai-mcp-dev-datacenter"
    Component = "datacenter"
  }
}

# ---------------------------------------------------------------------------
# Task execution role (pulls image from ECR, writes logs, injects secrets).
# ---------------------------------------------------------------------------
resource "aws_iam_role" "datacenter_task_exec" {
  name               = "ai-mcp-dev-datacenter-task-exec-role"
  assume_role_policy = data.aws_iam_policy_document.backend_ecs_assume.json

  tags = {
    Name      = "ai-mcp-dev-datacenter-task-exec-role"
    Component = "datacenter"
  }
}

resource "aws_iam_role_policy_attachment" "datacenter_task_exec_managed" {
  role       = aws_iam_role.datacenter_task_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "datacenter_task_exec_secret" {
  role       = aws_iam_role.datacenter_task_exec.name
  policy_arn = aws_iam_policy.rorr_secret_read.arn
}

# ---------------------------------------------------------------------------
# Task role (application runtime permissions).
# ---------------------------------------------------------------------------
resource "aws_iam_role" "datacenter_task" {
  name               = "ai-mcp-dev-datacenter-task-role"
  assume_role_policy = data.aws_iam_policy_document.backend_ecs_assume.json

  tags = {
    Name      = "ai-mcp-dev-datacenter-task-role"
    Component = "datacenter"
  }
}

resource "aws_iam_role_policy_attachment" "datacenter_task_secret" {
  role       = aws_iam_role.datacenter_task.name
  policy_arn = aws_iam_policy.rorr_secret_read.arn
}

# ---------------------------------------------------------------------------
# Task definition.
# ---------------------------------------------------------------------------
resource "aws_ecs_task_definition" "datacenter" {
  family                   = "ai-mcp-dev-datacenter"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.datacenter_task_exec.arn
  task_role_arn            = aws_iam_role.datacenter_task.arn

  container_definitions = jsonencode([
    {
      name      = "datacenter"
      image     = "${aws_ecr_repository.datacenter.repository_url}:latest"
      essential = true

      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "ENV", value = var.env },
        { name = "AWS_REGION", value = var.region },
      ]

      # Full secret ARN in valueFrom (never ARN#key) per infra rules.
      secrets = [
        { name = "RORR_SECRET_JSON", valueFrom = data.aws_secretsmanager_secret.rorr.arn }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.datacenter.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "datacenter"
        }
      }
    }
  ])

  tags = {
    Name      = "ai-mcp-dev-datacenter"
    Component = "datacenter"
  }
}

# ---------------------------------------------------------------------------
# Service on the shared backend cluster.
# ---------------------------------------------------------------------------
resource "aws_ecs_service" "datacenter" {
  name            = "ai-mcp-dev-datacenter-service"
  cluster         = aws_ecs_cluster.backend.id
  task_definition = aws_ecs_task_definition.datacenter.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.backend_ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.datacenter.arn
    container_name   = "datacenter"
    container_port   = 8080
  }

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  depends_on = [
    aws_lb_listener.datacenter_444,
    aws_iam_role_policy_attachment.datacenter_task_exec_managed,
  ]

  tags = {
    Name      = "ai-mcp-dev-datacenter-service"
    Component = "datacenter"
  }
}
