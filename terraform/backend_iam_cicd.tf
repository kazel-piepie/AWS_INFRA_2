# ---------------------------------------------------------------------------
# Dedicated IAM user for backend CI/CD (Git): reads a tightly-scoped set of
# secrets and deploys the backend Docker image to ECS. Least privilege only.
# ---------------------------------------------------------------------------
locals {
  account_id = data.aws_caller_identity.current.account_id
  region_id  = data.aws_region.current.name

  # Exact secret ARNs (with version suffix wildcard) the CI/CD user may read.
  backend_cicd_secret_arns = [
    "arn:aws:secretsmanager:${local.region_id}:${local.account_id}:secret:ai/rorr-infra/${var.env}-*",
    "arn:aws:secretsmanager:${local.region_id}:${local.account_id}:secret:ai/rorr/${var.env}-*",
  ]

  # ECS service ARN for the backend (scopes UpdateService / DescribeServices).
  backend_service_arn = "arn:aws:ecs:${local.region_id}:${local.account_id}:service/${aws_ecs_cluster.backend.name}/${aws_ecs_service.backend.name}"
}

resource "aws_iam_user" "backend_cicd" {
  name = "${local.name_prefix}-backend-cicd"
  path = "/cicd/"

  tags = {
    Name      = "${local.name_prefix}-backend-cicd"
    Component = "backend"
    Purpose   = "git-cicd-deploy"
  }
}

# Access key surfaced via Terraform outputs for storage as Git CI variables.
resource "aws_iam_access_key" "backend_cicd" {
  user = aws_iam_user.backend_cicd.name
}

data "aws_iam_policy_document" "backend_cicd" {
  # --- Secrets Manager: ONLY the two allowed secrets, read-only. ---
  statement {
    sid    = "ReadAllowedSecrets"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = local.backend_cicd_secret_arns
  }

  # --- ECS: update the backend service only. ---
  statement {
    sid    = "DeployBackendService"
    effect = "Allow"
    actions = [
      "ecs:UpdateService",
      "ecs:DescribeServices",
    ]
    resources = [local.backend_service_arn]
  }

  # RegisterTaskDefinition / DescribeTaskDefinition do not support
  # resource-level permissions; they must be granted on "*".
  statement {
    sid    = "BackendTaskDefinition"
    effect = "Allow"
    actions = [
      "ecs:RegisterTaskDefinition",
      "ecs:DescribeTaskDefinition",
    ]
    resources = ["*"]
  }

  # List / describe tasks, scoped to the backend cluster via condition.
  statement {
    sid    = "BackendClusterTasks"
    effect = "Allow"
    actions = [
      "ecs:ListTasks",
      "ecs:DescribeTasks",
    ]
    resources = ["*"]
    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [aws_ecs_cluster.backend.arn]
    }
  }

  # Run a standalone backend task (one-off jobs / migrations), scoped to any
  # revision of the backend task definition and limited to the backend cluster.
  statement {
    sid       = "RunBackendStandaloneTask"
    effect    = "Allow"
    actions   = ["ecs:RunTask"]
    resources = ["arn:aws:ecs:${local.region_id}:${local.account_id}:task-definition/${aws_ecs_task_definition.backend.family}:*"]
    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [aws_ecs_cluster.backend.arn]
    }
  }

  # PassRole limited to the backend task execution + task roles, and only to
  # the ECS tasks service.
  statement {
    sid     = "PassBackendEcsRoles"
    effect  = "Allow"
    actions = ["iam:PassRole"]
    resources = [
      aws_iam_role.backend_task_execution.arn,
      aws_iam_role.backend_task.arn,
    ]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  # ECR auth token is account-wide (no resource-level support).
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # ECR push/pull limited to the backend repository.
  statement {
    sid    = "EcrBackendRepo"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
    ]
    resources = [aws_ecr_repository.backend.arn]
  }
}

resource "aws_iam_user_policy" "backend_cicd" {
  name   = "${local.name_prefix}-backend-cicd-policy"
  user   = aws_iam_user.backend_cicd.name
  policy = data.aws_iam_policy_document.backend_cicd.json
}
