# ---------------------------------------------------------------------------
# Dedicated IAM user for frontend ECS CI/CD (Git): push Docker images to ECR
# and update the ECS service. Least privilege only.
# ---------------------------------------------------------------------------

locals {
  frontend_ecs_service_arn = "arn:aws:ecs:${local.region_id}:${local.account_id}:service/${aws_ecs_cluster.frontend_ecs.name}/${aws_ecs_service.frontend_ecs.name}"

  frontend_ecs_cicd_secret_arns = [
    "arn:aws:secretsmanager:${local.region_id}:${local.account_id}:secret:ai/rorr-infra/${var.env}-*",
  ]
}

resource "aws_iam_user" "frontend_ecs_cicd" {
  name = "${local.name_prefix}-frontend-ecs-cicd"
  path = "/cicd/"

  tags = {
    Name      = "${local.name_prefix}-frontend-ecs-cicd"
    Component = "frontend-ecs"
    Purpose   = "git-cicd-deploy"
  }
}

resource "aws_iam_access_key" "frontend_ecs_cicd" {
  user = aws_iam_user.frontend_ecs_cicd.name
}

data "aws_iam_policy_document" "frontend_ecs_cicd" {
  statement {
    sid    = "ReadInfraSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = local.frontend_ecs_cicd_secret_arns
  }

  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrFrontendEcsRepo"
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
    resources = [aws_ecr_repository.frontend_ecs.arn]
  }

  statement {
    sid    = "DeployFrontendEcsService"
    effect = "Allow"
    actions = [
      "ecs:UpdateService",
      "ecs:DescribeServices",
    ]
    resources = [local.frontend_ecs_service_arn]
  }

  statement {
    sid    = "FrontendEcsTaskDefinition"
    effect = "Allow"
    actions = [
      "ecs:RegisterTaskDefinition",
      "ecs:DescribeTaskDefinition",
    ]
    resources = ["*"]
  }

  statement {
    sid     = "PassFrontendEcsRoles"
    effect  = "Allow"
    actions = ["iam:PassRole"]
    resources = [
      aws_iam_role.frontend_ecs_task_execution.arn,
      aws_iam_role.frontend_ecs_task.arn,
    ]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_user_policy" "frontend_ecs_cicd" {
  name   = "${local.name_prefix}-frontend-ecs-cicd-policy"
  user   = aws_iam_user.frontend_ecs_cicd.name
  policy = data.aws_iam_policy_document.frontend_ecs_cicd.json
}

resource "aws_secretsmanager_secret" "frontend_ecs_cicd_key" {
  name        = "ai/rorr-infra/${var.env}-frontend-ecs-cicd-key"
  description = "Access key for the RORR frontend ECS CI/CD IAM user"

  tags = {
    Name      = "ai/rorr-infra/${var.env}-frontend-ecs-cicd-key"
    Component = "frontend-ecs"
    Purpose   = "cicd-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "frontend_ecs_cicd_key" {
  secret_id = aws_secretsmanager_secret.frontend_ecs_cicd_key.id
  secret_string = jsonencode({
    aws_access_key_id     = aws_iam_access_key.frontend_ecs_cicd.id
    aws_secret_access_key = aws_iam_access_key.frontend_ecs_cicd.secret
    user_name             = aws_iam_user.frontend_ecs_cicd.name
  })
}
