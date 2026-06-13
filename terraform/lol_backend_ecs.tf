# ---------------------------------------------------------------------------
# LOL backend pipeline: 8 Fargate services running on the EXISTING backend
# cluster (ai-rorr-develop-backend-cluster). No new cluster is created.
# All are background workers/deliverers - no ALB, no inbound ports.
# ---------------------------------------------------------------------------
locals {
  # Exact service names per task spec (no ai- prefix).
  lol_modules = toset([
    "rorr-lol-collector",
    "rorr-lol-raw-store",
    "rorr-lol-processor",
    "rorr-lol-processed-store",
    "rorr-lol-contextualizer",
    "rorr-lol-processed-deliverer",
    "rorr-lol-context-store",
    "rorr-lol-context-deliverer",
  ])

  # Existing backend cluster - referenced, never recreated.
  lol_cluster_name = aws_ecs_cluster.backend.name
  lol_cluster_arn  = aws_ecs_cluster.backend.arn

  # Container entrypoint module = service name without the "rorr-lol-" prefix
  # (e.g. rorr-lol-collector -> node dist/collector).
  lol_module_entrypoint = { for name in local.lol_modules : name => replace(name, "rorr-lol-", "") }

  # MSK topic ARN prefix derived from the cluster ARN (cluster/ -> topic/), so
  # topic ARNs need no hardcoded cluster UUID.
  msk_topic_arn_prefix = replace(aws_msk_cluster.main.arn, ":cluster/", ":topic/")
}

# One log group per service: /ecs/rorr-lol-<module>.
resource "aws_cloudwatch_log_group" "lol" {
  for_each = local.lol_modules

  name              = "/ecs/${each.value}"
  retention_in_days = 14

  tags = {
    Name      = "/ecs/${each.value}"
    Component = "lol-backend"
  }
}

# Task definition per module. Single shared image, module-specific command and
# task role; shared execution role. Develop sizing: 256 CPU / 512 MiB.
resource "aws_ecs_task_definition" "lol" {
  for_each = local.lol_modules

  family                   = each.value
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.rorr_lol_execution_role.arn
  task_role_arn            = local.rorr_lol_task_roles[each.value].arn

  container_definitions = jsonencode([
    {
      name      = each.value
      image     = "${aws_ecr_repository.lol_backend.repository_url}:latest"
      essential = true
      command   = ["node", "dist/${local.lol_module_entrypoint[each.value]}"]

      environment = [
        { name = "APP_ENV", value = var.env },
        { name = "AWS_REGION", value = var.region },
      ]

      # Full secret ARN in valueFrom (never ARN#key) per infra rules.
      secrets = [
        { name = "RORR_SECRET_JSON", valueFrom = data.aws_secretsmanager_secret.rorr.arn },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.lol[each.value].name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = each.value
        }
      }
    }
  ])

  tags = {
    Name      = each.value
    Component = "lol-backend"
  }
}

# Service per module on the existing backend cluster. desired_count = 0 for the
# initial deploy (collector is scale-controlled at runtime; the rest are started
# manually). CI/CD rolls image/task-definition out of band, so ignore drift.
resource "aws_ecs_service" "lol" {
  for_each = local.lol_modules

  name            = each.value
  cluster         = aws_ecs_cluster.backend.id
  task_definition = aws_ecs_task_definition.lol[each.value].arn
  desired_count   = 0
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.backend_ecs.id]
    assign_public_ip = false
  }

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  tags = {
    Name      = each.value
    Component = "lol-backend"
  }
}
