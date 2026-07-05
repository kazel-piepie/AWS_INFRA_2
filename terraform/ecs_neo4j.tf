# ---------------------------------------------------------------------------
# Neo4j ECS Fargate stack (rorr-lol-datacenter-neo4j).
#
# A dedicated ECS cluster + ECR repo + service for the LOL datacenter Neo4j
# workload. Unlike the lol_backend pipeline (which runs on the shared backend
# cluster), this workload gets its own cluster and its own task execution role.
#
# Existing resources are referenced, never recreated:
#   - VPC / private subnets: defined in vpc.tf as resources -> referenced
#     directly (aws_vpc.main, aws_subnet.private).
#   - Neo4j security group (ai-rorr-<env>-neo4j-sg): looked up as a data source.
#   - Neo4j task role (ai-rorr-<env>-neo4j-role): looked up as a data source.
#   - ai/rorr/<env> secret: reuses the existing data.aws_secretsmanager_secret.rorr
#     from data.tf (declaring it again here would be a duplicate).
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Data sources — existing resources referenced, not recreated.
# ---------------------------------------------------------------------------

# Existing Neo4j security group, matched by name within the RORR VPC.
data "aws_security_group" "neo4j" {
  filter {
    name   = "group-name"
    values = ["${local.name_prefix}-neo4j-sg"]
  }

  filter {
    name   = "vpc-id"
    values = [aws_vpc.main.id]
  }
}

# Existing Neo4j task role (application runtime permissions).
data "aws_iam_role" "neo4j_task" {
  name = "${local.name_prefix}-neo4j-role"
}

# ---------------------------------------------------------------------------
# 1. ECR repository for the Neo4j image.
# ---------------------------------------------------------------------------
resource "aws_ecr_repository" "neo4j" {
  name                 = "${local.name_prefix}-neo4j"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name      = "${local.name_prefix}-neo4j"
    Component = "neo4j"
  }
}

# ---------------------------------------------------------------------------
# 2. Dedicated ECS cluster for the Neo4j workload.
# ---------------------------------------------------------------------------
resource "aws_ecs_cluster" "neo4j" {
  name = "${local.name_prefix}-backend-neo4j-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name      = "${local.name_prefix}-backend-neo4j-cluster"
    Component = "neo4j"
  }
}

# ---------------------------------------------------------------------------
# 3. Dedicated task execution role (NEW — not the shared backend exec role).
#    Pulls the image from ECR, writes logs, and injects secrets.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "neo4j_ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "neo4j_task_exec" {
  name               = "${local.name_prefix}-neo4j-task-exec-role"
  assume_role_policy = data.aws_iam_policy_document.neo4j_ecs_assume.json

  tags = {
    Name      = "${local.name_prefix}-neo4j-task-exec-role"
    Component = "neo4j"
  }
}

resource "aws_iam_role_policy_attachment" "neo4j_task_exec_managed" {
  role       = aws_iam_role.neo4j_task_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Inline policy: read only the two secrets this workload needs (exact ARNs,
# no wildcards) for secret injection into the container.
data "aws_iam_policy_document" "neo4j_task_exec_secrets" {
  statement {
    sid    = "ReadNeo4jTaskSecrets"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
    ]
    resources = [
      data.aws_secretsmanager_secret.rorr.arn,
      aws_secretsmanager_secret.neo4j_ecs.arn,
    ]
  }
}

resource "aws_iam_role_policy" "neo4j_task_exec_secrets" {
  name   = "${local.name_prefix}-neo4j-task-exec-secrets"
  role   = aws_iam_role.neo4j_task_exec.id
  policy = data.aws_iam_policy_document.neo4j_task_exec_secrets.json
}

# ---------------------------------------------------------------------------
# 4. Secrets Manager secret describing where the Neo4j ECS workload lives.
#    Consumed by CI/CD to target the correct ECR repo / cluster / service.
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "neo4j_ecs" {
  name        = "rorr/${var.env}/ecs-services/neo4j"
  description = "RORR Neo4j ECS service deployment references"

  tags = {
    Name      = "rorr-${var.env}-ecs-services-neo4j"
    Component = "neo4j"
  }
}

resource "aws_secretsmanager_secret_version" "neo4j_ecs" {
  secret_id = aws_secretsmanager_secret.neo4j_ecs.id
  secret_string = jsonencode({
    ecr_repository_url = aws_ecr_repository.neo4j.repository_url
    ecs_cluster_name   = aws_ecs_cluster.neo4j.name
    ecs_service_name   = "rorr-lol-datacenter-neo4j"
  })
}

# ---------------------------------------------------------------------------
# 6. CloudWatch log group for the Neo4j service.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "neo4j" {
  name              = "/ecs/rorr-lol-datacenter-neo4j"
  retention_in_days = 7

  tags = {
    Name      = "/ecs/rorr-lol-datacenter-neo4j"
    Component = "neo4j"
  }
}

# ---------------------------------------------------------------------------
# 7. Task definition.
# ---------------------------------------------------------------------------
resource "aws_ecs_task_definition" "neo4j" {
  family                   = "rorr-lol-datacenter-neo4j"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.neo4j_task_exec.arn
  task_role_arn            = data.aws_iam_role.neo4j_task.arn

  container_definitions = jsonencode([
    {
      name      = "rorr-lol-datacenter-neo4j"
      image     = "${aws_ecr_repository.neo4j.repository_url}:latest"
      essential = true

      # Full secret ARN in valueFrom (never ARN#key) per infra rules.
      secrets = [
        { name = "RORR_SECRET_JSON", valueFrom = data.aws_secretsmanager_secret.rorr.arn },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.neo4j.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = {
    Name      = "rorr-lol-datacenter-neo4j"
    Component = "neo4j"
  }
}

# ---------------------------------------------------------------------------
# 8. ECS service on the dedicated Neo4j cluster.
# ---------------------------------------------------------------------------
resource "aws_ecs_service" "neo4j" {
  name            = "rorr-lol-datacenter-neo4j"
  cluster         = aws_ecs_cluster.neo4j.id
  task_definition = aws_ecs_task_definition.neo4j.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [data.aws_security_group.neo4j.id]
    assign_public_ip = false
  }

  tags = {
    Name      = "rorr-lol-datacenter-neo4j"
    Component = "neo4j"
  }
}
