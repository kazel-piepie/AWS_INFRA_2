# ---------------------------------------------------------------------------
# RORR Next.js SSR frontend ECS infrastructure: ECR, ECS cluster, ALB,
# CloudFront distribution.
# Served at local.frontend_ecs_app_domain (ai-tmp-{dev/prod}-app.rorr.club).
# ---------------------------------------------------------------------------

# AWS-managed prefix list for CloudFront origin-facing IPs (restricts ALB SG).
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

# AWS-managed CachingDisabled cache policy (SSR must not be cached at edge).
data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

# AWS-managed AllViewerExceptHostHeader origin request policy.
data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

# ---------------------------------------------------------------------------
# ECR repository for the frontend ECS Docker image.
# ---------------------------------------------------------------------------
resource "aws_ecr_repository" "frontend_ecs" {
  name                 = "${local.name_prefix}-frontend-ecs"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name      = "${local.name_prefix}-frontend-ecs"
    Component = "frontend-ecs"
  }
}

resource "aws_ecr_lifecycle_policy" "frontend_ecs" {
  repository = aws_ecr_repository.frontend_ecs.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

# ---------------------------------------------------------------------------
# Security groups.
# ---------------------------------------------------------------------------
resource "aws_security_group" "frontend_ecs_alb" {
  name        = "${local.name_prefix}-frontend-ecs-alb-sg"
  description = "RORR frontend ECS ALB HTTPS from CloudFront only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from CloudFront"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-frontend-ecs-alb-sg"
  }
}

resource "aws_security_group" "frontend_ecs_task" {
  name        = "${local.name_prefix}-frontend-ecs-task-sg"
  description = "RORR frontend ECS Fargate tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "App traffic from frontend ECS ALB"
    from_port       = var.frontend_ecs_container_port
    to_port         = var.frontend_ecs_container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend_ecs_alb.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-frontend-ecs-task-sg"
  }
}

# ---------------------------------------------------------------------------
# ALB (internet-facing; CloudFront sits in front as the public entry point).
# ---------------------------------------------------------------------------
resource "aws_lb" "frontend_ecs" {
  name               = "${local.name_prefix}-frontend-ecs-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.frontend_ecs_alb.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name      = "${local.name_prefix}-frontend-ecs-alb"
    Component = "frontend-ecs"
  }
}

resource "aws_lb_target_group" "frontend_ecs" {
  name        = "${local.name_prefix}-frontend-ecs-tg"
  port        = var.frontend_ecs_container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = var.frontend_ecs_health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = {
    Name      = "${local.name_prefix}-frontend-ecs-tg"
    Component = "frontend-ecs"
  }
}

resource "aws_lb_listener" "frontend_ecs_https" {
  load_balancer_arn = aws_lb.frontend_ecs.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = data.aws_acm_certificate.rorr_club.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend_ecs.arn
  }

  tags = {
    Name = "${local.name_prefix}-frontend-ecs-https"
  }
}

resource "aws_lb_listener" "frontend_ecs_http" {
  load_balancer_arn = aws_lb.frontend_ecs.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = {
    Name = "${local.name_prefix}-frontend-ecs-http-redirect"
  }
}

# ---------------------------------------------------------------------------
# ECS cluster.
# ---------------------------------------------------------------------------
resource "aws_ecs_cluster" "frontend_ecs" {
  name = "${local.name_prefix}-frontend-ecs-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name      = "${local.name_prefix}-frontend-ecs-cluster"
    Component = "frontend-ecs"
  }
}

resource "aws_cloudwatch_log_group" "frontend_ecs" {
  name              = "/ecs/${local.name_prefix}-frontend-ecs"
  retention_in_days = 14

  tags = {
    Name      = "${local.name_prefix}-frontend-ecs"
    Component = "frontend-ecs"
  }
}

# ---------------------------------------------------------------------------
# Task execution role.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "frontend_ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "frontend_ecs_task_execution" {
  name               = "${local.name_prefix}-frontend-ecs-exec-role"
  assume_role_policy = data.aws_iam_policy_document.frontend_ecs_assume.json

  tags = {
    Name      = "${local.name_prefix}-frontend-ecs-exec-role"
    Component = "frontend-ecs"
  }
}

resource "aws_iam_role_policy_attachment" "frontend_ecs_task_execution_managed" {
  role       = aws_iam_role.frontend_ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "frontend_ecs_logs_create" {
  statement {
    sid       = "CreateFrontendEcsLogGroup"
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup"]
    resources = ["arn:aws:logs:${local.region_id}:${local.account_id}:log-group:/ecs/${local.name_prefix}-frontend-ecs:*"]
  }
}

resource "aws_iam_role_policy" "frontend_ecs_logs_create" {
  name   = "${local.name_prefix}-frontend-ecs-logs-create"
  role   = aws_iam_role.frontend_ecs_task_execution.id
  policy = data.aws_iam_policy_document.frontend_ecs_logs_create.json
}

# ---------------------------------------------------------------------------
# Task role (application runtime permissions).
# ---------------------------------------------------------------------------
resource "aws_iam_role" "frontend_ecs_task" {
  name               = "${local.name_prefix}-frontend-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.frontend_ecs_assume.json

  tags = {
    Name      = "${local.name_prefix}-frontend-ecs-task-role"
    Component = "frontend-ecs"
  }
}

data "aws_iam_policy_document" "frontend_ecs_exec_ssm" {
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

resource "aws_iam_role_policy" "frontend_ecs_exec_ssm" {
  name   = "${local.name_prefix}-frontend-ecs-exec-ssm"
  role   = aws_iam_role.frontend_ecs_task.id
  policy = data.aws_iam_policy_document.frontend_ecs_exec_ssm.json
}

# ---------------------------------------------------------------------------
# Task definition.
# ---------------------------------------------------------------------------
resource "aws_ecs_task_definition" "frontend_ecs" {
  family                   = "${local.name_prefix}-frontend-ecs-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.frontend_ecs_cpu
  memory                   = var.frontend_ecs_memory
  execution_role_arn       = aws_iam_role.frontend_ecs_task_execution.arn
  task_role_arn            = aws_iam_role.frontend_ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "frontend-ecs"
      image     = "${aws_ecr_repository.frontend_ecs.repository_url}:latest"
      essential = true

      portMappings = [
        {
          containerPort = var.frontend_ecs_container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "ENV", value = var.env },
        { name = "AWS_REGION", value = var.region }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.frontend_ecs.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "frontend-ecs"
        }
      }
    }
  ])

  tags = {
    Name      = "${local.name_prefix}-frontend-ecs-task"
    Component = "frontend-ecs"
  }
}

# ---------------------------------------------------------------------------
# ECS service.
# ---------------------------------------------------------------------------
resource "aws_ecs_service" "frontend_ecs" {
  name            = "${local.name_prefix}-frontend-ecs-service"
  cluster         = aws_ecs_cluster.frontend_ecs.id
  task_definition = aws_ecs_task_definition.frontend_ecs.arn
  desired_count   = var.frontend_ecs_desired_count
  launch_type     = "FARGATE"

  enable_execute_command = true

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.frontend_ecs_task.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend_ecs.arn
    container_name   = "frontend-ecs"
    container_port   = var.frontend_ecs_container_port
  }

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  depends_on = [aws_lb_listener.frontend_ecs_https]

  tags = {
    Name      = "${local.name_prefix}-frontend-ecs-service"
    Component = "frontend-ecs"
  }
}

# ---------------------------------------------------------------------------
# CloudFront distribution (ALB custom origin, CachingDisabled for SSR).
# ---------------------------------------------------------------------------
resource "aws_cloudfront_distribution" "frontend_ecs" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "RORR frontend ECS SSR distribution (${var.env})"
  aliases         = [local.frontend_ecs_app_domain]
  price_class     = "PriceClass_100"

  origin {
    domain_name = aws_lb.frontend_ecs.dns_name
    origin_id   = "alb-${local.name_prefix}-frontend-ecs"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id         = "alb-${local.name_prefix}-frontend-ecs"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = data.aws_acm_certificate.rorr_club.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    Name      = "${local.name_prefix}-frontend-ecs"
    Component = "frontend-ecs"
    Purpose   = "cdn"
  }
}

# ---------------------------------------------------------------------------
# Persist the frontend_ecs group into ai/rorr-infra/${env} after apply.
# Read-modify-write merge (jq) so other keys in the secret are preserved.
# ---------------------------------------------------------------------------
resource "null_resource" "frontend_ecs_secret" {
  triggers = {
    alb_dns         = aws_lb.frontend_ecs.dns_name
    distribution_id = aws_cloudfront_distribution.frontend_ecs.id
    domain_name     = aws_cloudfront_distribution.frontend_ecs.domain_name
    cluster_name    = aws_ecs_cluster.frontend_ecs.name
    service_name    = aws_ecs_service.frontend_ecs.name
    ecr_url         = aws_ecr_repository.frontend_ecs.repository_url
    secret_id       = data.aws_secretsmanager_secret.rorr_infra.id
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      GROUP=$(jq -n \
        --arg alb_dns   "${aws_lb.frontend_ecs.dns_name}" \
        --arg distid    "${aws_cloudfront_distribution.frontend_ecs.id}" \
        --arg domain    "${aws_cloudfront_distribution.frontend_ecs.domain_name}" \
        --arg distarn   "${aws_cloudfront_distribution.frontend_ecs.arn}" \
        --arg alias     "${local.frontend_ecs_app_domain}" \
        --arg status    "${aws_cloudfront_distribution.frontend_ecs.status}" \
        --arg cluster   "${aws_ecs_cluster.frontend_ecs.name}" \
        --arg service   "${aws_ecs_service.frontend_ecs.name}" \
        --arg ecr       "${aws_ecr_repository.frontend_ecs.repository_url}" \
        --arg iamuser   "${aws_iam_user.frontend_ecs_cicd.name}" \
        --arg keysecret "${aws_secretsmanager_secret.frontend_ecs_cicd_key.name}" \
        '{
          "frontend_ecs": {
            alb: {
              dns: $alb_dns
            },
            cloudfront: {
              distribution_id: $distid,
              domain_name:     $domain,
              arn:             $distarn,
              alias:           $alias,
              status:          $status
            },
            ecs: {
              cluster_name:   $cluster,
              service_name:   $service,
              ecr_repository: $ecr
            },
            cicd: {
              iam_user:    $iamuser,
              secret_name: $keysecret
            }
          }
        }')

      CURRENT=$(aws secretsmanager get-secret-value \
        --secret-id "${data.aws_secretsmanager_secret.rorr_infra.id}" \
        --region "${var.region}" \
        --query SecretString --output text --no-cli-pager)

      UPDATED=$(echo "$CURRENT" | jq --argjson group "$GROUP" '. * $group')

      aws secretsmanager put-secret-value \
        --secret-id "${data.aws_secretsmanager_secret.rorr_infra.id}" \
        --region "${var.region}" \
        --secret-string "$UPDATED" \
        --no-cli-pager
    EOT
  }

  depends_on = [
    aws_cloudfront_distribution.frontend_ecs,
    aws_ecs_service.frontend_ecs,
  ]
}
