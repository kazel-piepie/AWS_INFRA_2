# Data sources for the backend service.

# Current account (used to build exact ECS/IAM resource ARNs without wildcards).
data "aws_caller_identity" "current" {}

# Pre-existing RORR infrastructure secret (VPC/ECR/ECS/ALB references), created
# by the MCP server prerequisite work. Referenced as a data source, never
# created here. Its exact ARN (including the random suffix) is granted to the
# backend CI/CD user and task roles.
data "aws_secretsmanager_secret" "rorr_infra" {
  name = "ai/rorr-infra/${var.env}"
}

# Issued ACM certificate for rorr.club (wildcard) used by the HTTPS listener.
data "aws_acm_certificate" "rorr" {
  domain      = var.backend_cert_domain
  statuses    = ["ISSUED"]
  most_recent = true
}

locals {
  backend_name = "${local.name_prefix}-backend"

  # Exact ARNs (no wildcards) for least-privilege CI/CD scoping.
  backend_cluster_arn = "arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:cluster/${local.backend_name}-cluster"
  backend_service_arn = "arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:service/${local.backend_name}-cluster/${local.backend_name}-service"
}
