# ---------------------------------------------------------------------------
# GitHub Actions OIDC: federated deploy role for the LOL backend pipeline.
# No long-lived access keys - CI/CD assumes rorr-lol-deploy-develop via OIDC.
# The account had no token.actions.githubusercontent.com provider (verified via
# `aws iam list-open-id-connect-providers`), so it is created here.
# ---------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]

  tags = {
    Name      = "github-actions-oidc"
    Component = "lol-backend"
  }
}

# Trust policy: GitHub OIDC, repo kazel-piepie/AWS_INFRA_2, develop branch only.
data "aws_iam_policy_document" "lol_deploy_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:kazel-piepie/AWS_INFRA_2:ref:refs/heads/develop"]
    }
  }
}

resource "aws_iam_role" "lol_deploy" {
  name               = "rorr-lol-deploy-develop"
  assume_role_policy = data.aws_iam_policy_document.lol_deploy_assume.json

  tags = {
    Name      = "rorr-lol-deploy-develop"
    Component = "lol-backend"
    Purpose   = "github-oidc-deploy"
  }
}

# Wildcard ARN matching every rorr-lol-* service on the existing cluster.
locals {
  lol_service_arn_wildcard = "arn:aws:ecs:${local.region_id}:${local.account_id}:service/${local.lol_cluster_name}/rorr-lol-*"

  # PassRole targets: the shared execution role + all module task roles.
  lol_passrole_arns = concat(
    [aws_iam_role.rorr_lol_execution_role.arn],
    [for r in local.rorr_lol_task_roles : r.arn],
  )
}

data "aws_iam_policy_document" "lol_deploy" {
  # Read the rorr secret (ecs-services key) to resolve service/task settings.
  statement {
    sid       = "ReadRorrSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [data.aws_secretsmanager_secret.rorr.arn]
  }

  # Roll the rorr-lol-* services.
  statement {
    sid       = "DeployLolServices"
    effect    = "Allow"
    actions   = ["ecs:DescribeServices", "ecs:UpdateService"]
    resources = [local.lol_service_arn_wildcard]
  }

  # Register/Describe task definitions do not support resource-level scoping.
  statement {
    sid    = "TaskDefinitions"
    effect = "Allow"
    actions = [
      "ecs:DescribeTaskDefinition",
      "ecs:RegisterTaskDefinition",
    ]
    resources = ["*"]
  }

  # PassRole limited to the LOL task/execution roles, ECS tasks service only.
  statement {
    sid       = "PassLolRoles"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = local.lol_passrole_arns
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

  # ECR push limited to the rorr-lol-backend repository.
  statement {
    sid    = "EcrPushLolBackend"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
    ]
    resources = [aws_ecr_repository.lol_backend.arn]
  }
}

resource "aws_iam_role_policy" "lol_deploy" {
  name   = "rorr-lol-deploy-develop-policy"
  role   = aws_iam_role.lol_deploy.id
  policy = data.aws_iam_policy_document.lol_deploy.json
}
