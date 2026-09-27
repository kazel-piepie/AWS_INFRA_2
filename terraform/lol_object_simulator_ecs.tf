# ---------------------------------------------------------------------------
# rorr-lol-object-simulator: always-on Fargate service on the EXISTING backend
# cluster (ai-rorr-develop-backend-cluster). Unlike the 10 background pipeline
# modules in lol_backend_ecs.tf, the simulator serves HTTP on port 3000 and is
# fronted by its own internet-facing ALB (alb_simulator.tf), so it is defined
# standalone rather than through the generic for_each. It shares the same ECR
# image, shared execution role, and log-group / secret-injection conventions.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "object_simulator" {
  name              = "/ecs/rorr-lol-object-simulator"
  retention_in_days = 14

  tags = {
    Name      = "/ecs/rorr-lol-object-simulator"
    Component = "lol-backend"
  }
}

resource "aws_ecs_task_definition" "object_simulator" {
  family                   = "rorr-lol-object-simulator"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.simulator_cpu
  memory                   = var.simulator_memory
  execution_role_arn       = aws_iam_role.rorr_lol_execution_role.arn
  task_role_arn            = aws_iam_role.rorr_lol_object_simulator_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "rorr-lol-object-simulator"
      image     = "${aws_ecr_repository.lol_backend.repository_url}:latest"
      essential = true
      command   = ["node", "dist/object-simulator"]

      portMappings = [
        {
          containerPort = var.simulator_container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "APP_ENV", value = var.env },
        { name = "AWS_REGION", value = var.region },
      ]

      # Full secret ARN in valueFrom (never ARN#key) per infra rules. The
      # kafka / database / redis secrets (rorr/${var.env}/*) are read by the app
      # at runtime via the task role's AppSecrets grant.
      secrets = [
        { name = "RORR_SECRET_JSON", valueFrom = data.aws_secretsmanager_secret.rorr.arn },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.object_simulator.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "rorr-lol-object-simulator"
        }
      }
    }
  ])

  tags = {
    Name      = "rorr-lol-object-simulator"
    Component = "lol-backend"
  }
}

resource "aws_ecs_service" "object_simulator" {
  name            = "rorr-lol-object-simulator"
  cluster         = aws_ecs_cluster.backend.id
  task_definition = aws_ecs_task_definition.object_simulator.arn
  desired_count   = var.simulator_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.sim_ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.simulator.arn
    container_name   = "rorr-lol-object-simulator"
    container_port   = var.simulator_container_port
  }

  # CI/CD rolls the image/task-definition out of band; ignore those drifts.
  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  depends_on = [aws_lb_listener.simulator_https]

  tags = {
    Name      = "rorr-lol-object-simulator"
    Component = "lol-backend"
  }
}
