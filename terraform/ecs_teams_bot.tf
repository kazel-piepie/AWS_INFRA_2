# Teams Bot ECS Fargate service. Runs the Microsoft Teams bot that reads from
# Neo4j and the main DB (read-only) and serves the Teams messaging endpoint
# behind an internet-facing ALB (see alb_teams_bot.tf).

# ---------------------------------------------------------------------------
# Secrets Manager — teams bot credentials and ECS deployment references.
# These are created (not data-referenced) here; runtime code fills in the empty
# placeholder values out of band. Descriptions are ASCII only.
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "neo4j_reader" {
  name        = "rorr/${var.env}/neo4j/reader"
  description = "RORR Neo4j read-only credentials for teams bot"

  tags = {
    Name      = "rorr-${var.env}-neo4j-reader"
    Component = "teams-bot"
  }
}

resource "aws_secretsmanager_secret_version" "neo4j_reader" {
  secret_id = aws_secretsmanager_secret.neo4j_reader.id
  secret_string = jsonencode({
    uri      = ""
    username = ""
    password = ""
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret" "db_reader" {
  name        = "rorr/${var.env}/database/reader"
  description = "RORR database read-only credentials for teams bot"

  tags = {
    Name      = "rorr-${var.env}-database-reader"
    Component = "teams-bot"
  }
}

resource "aws_secretsmanager_secret_version" "db_reader" {
  secret_id = aws_secretsmanager_secret.db_reader.id
  secret_string = jsonencode({
    host     = ""
    port     = 5432
    username = ""
    password = ""
    sslmode  = "disable"
    databases = {
      rorr_datacenter  = "rorr_datacenter"
      rorr_lol_service = "rorr_lol_service"
    }
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret" "teams_bot_app" {
  name        = "rorr/${var.env}/teams-bot"
  description = "Microsoft Teams bot application credentials"

  tags = {
    Name      = "rorr-${var.env}-teams-bot"
    Component = "teams-bot"
  }
}

resource "aws_secretsmanager_secret_version" "teams_bot_app" {
  secret_id = aws_secretsmanager_secret.teams_bot_app.id
  secret_string = jsonencode({
    teams_bot_id     = ""
    teams_bot_secret = ""
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret" "teams_bot_ecs" {
  name        = "rorr/${var.env}/ecs-services/teams-bot"
  description = "RORR Teams Bot ECS service deployment references"

  tags = {
    Name      = "rorr-${var.env}-ecs-services-teams-bot"
    Component = "teams-bot"
  }
}

resource "aws_secretsmanager_secret_version" "teams_bot_ecs" {
  secret_id = aws_secretsmanager_secret.teams_bot_ecs.id
  secret_string = jsonencode({
    ecr_repository_url = aws_ecr_repository.teams_bot.repository_url
    ecs_cluster_name   = aws_ecs_cluster.teams_bot.name
    ecs_services = {
      teams_bot = "rorr-lol-teams-bot"
    }
  })
}

# ---------------------------------------------------------------------------
# ECR repository for the teams bot Docker image.
# ---------------------------------------------------------------------------
resource "aws_ecr_repository" "teams_bot" {
  name                 = "${local.name_prefix}-teams-bot"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name      = "${local.name_prefix}-teams-bot"
    Component = "teams-bot"
  }
}

# ---------------------------------------------------------------------------
# Task execution role (pulls image from ECR, writes logs, injects secrets).
# ---------------------------------------------------------------------------
resource "aws_iam_role" "teams_bot_exec" {
  name               = "${local.name_prefix}-teams-bot-exec-role"
  assume_role_policy = data.aws_iam_policy_document.teams_bot_assume.json

  tags = {
    Name      = "${local.name_prefix}-teams-bot-exec-role"
    Component = "teams-bot"
  }
}

data "aws_iam_policy_document" "teams_bot_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "teams_bot_exec_managed" {
  role       = aws_iam_role.teams_bot_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "teams_bot_exec_secrets" {
  name = "${local.name_prefix}-teams-bot-exec-secrets"
  role = aws_iam_role.teams_bot_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      Resource = [
        aws_secretsmanager_secret.neo4j_reader.arn,
      ]
    }]
  })
}

# ---------------------------------------------------------------------------
# Task role (application runtime reads the teams bot secrets from SM).
# ---------------------------------------------------------------------------
resource "aws_iam_role" "teams_bot_task" {
  name               = "${local.name_prefix}-teams-bot-task-role"
  assume_role_policy = data.aws_iam_policy_document.teams_bot_assume.json

  tags = {
    Name      = "${local.name_prefix}-teams-bot-task-role"
    Component = "teams-bot"
  }
}

data "aws_iam_policy_document" "teams_bot_task_secret" {
  statement {
    sid    = "ReadTeamsBotSecrets"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [
      aws_secretsmanager_secret.neo4j_reader.arn,
      aws_secretsmanager_secret.db_reader.arn,
      aws_secretsmanager_secret.teams_bot_app.arn,
    ]
  }

  statement {
    sid    = "BedrockInvokeClaude"
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
      "arn:aws:bedrock:us-east-1:161327178737:inference-profile/us.anthropic.claude-sonnet-4-6-20251001-v1:0",
      "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-sonnet-4-6-20251001-v1:0",
      "arn:aws:bedrock:us-east-2::foundation-model/anthropic.claude-sonnet-4-6-20251001-v1:0",
      "arn:aws:bedrock:us-west-2::foundation-model/anthropic.claude-sonnet-4-6-20251001-v1:0",
    ]
  }
}

resource "aws_iam_role_policy" "teams_bot_task_secret" {
  name   = "teams-bot-task-secret-policy"
  role   = aws_iam_role.teams_bot_task.id
  policy = data.aws_iam_policy_document.teams_bot_task_secret.json
}

# ---------------------------------------------------------------------------
# ECS cluster, log group, task definition, service.
# ---------------------------------------------------------------------------
resource "aws_ecs_cluster" "teams_bot" {
  name = "${local.name_prefix}-teams-bot-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name      = "${local.name_prefix}-teams-bot-cluster"
    Component = "teams-bot"
  }
}

resource "aws_cloudwatch_log_group" "teams_bot" {
  name              = "/ecs/rorr-lol-teams-bot"
  retention_in_days = 7

  tags = {
    Name      = "/ecs/rorr-lol-teams-bot"
    Component = "teams-bot"
  }
}

resource "aws_ecs_task_definition" "teams_bot" {
  family                   = "rorr-lol-teams-bot"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.teams_bot_exec.arn
  task_role_arn            = aws_iam_role.teams_bot_task.arn

  container_definitions = jsonencode([
    {
      name      = "rorr-lol-teams-bot"
      image     = "${aws_ecr_repository.teams_bot.repository_url}:latest"
      essential = true

      portMappings = [
        {
          containerPort = 3978
          protocol      = "tcp"
        }
      ]

      # Full secret ARN in valueFrom (never ARN#key) per infra rules.
      secrets = [
        { name = "RORR_NEO4J_READER_JSON", valueFrom = aws_secretsmanager_secret.neo4j_reader.arn }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.teams_bot.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = {
    Name      = "rorr-lol-teams-bot"
    Component = "teams-bot"
  }
}

resource "aws_ecs_service" "teams_bot" {
  name            = "rorr-lol-teams-bot"
  cluster         = aws_ecs_cluster.teams_bot.id
  task_definition = aws_ecs_task_definition.teams_bot.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.teams_bot.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.teams_bot.arn
    container_name   = "rorr-lol-teams-bot"
    container_port   = 3978
  }

  depends_on = [aws_lb_listener.teams_bot_https]

  tags = {
    Name      = "rorr-lol-teams-bot"
    Component = "teams-bot"
  }
}
