# ---------------------------------------------------------------------------
# Dedicated IAM user for the DataCenter CI/CD deploy pipeline.
#
# This user lets GitHub Actions (or any external CI/CD runner) build and push
# the RORR develop Docker images. Least privilege only.
# ---------------------------------------------------------------------------

locals {
  # All develop RORR ECR repositories the pipeline pushes/pulls.
  datacenter_cicd_ecr_repo_arns = [
    aws_ecr_repository.backend.arn,
    aws_ecr_repository.lol_backend.arn,
  ]
}

# Externally-created secret holding the LOL backend ECS service references.
# Referenced as a data source per infra rules; never managed here.
data "aws_secretsmanager_secret" "rorr_ecs_services" {
  name = "rorr/develop/ecs-services"
}

resource "aws_iam_user" "datacenter_cicd" {
  name = "${local.name_prefix}-datacenter-cicd"
  path = "/cicd/"

  tags = {
    Name      = "${local.name_prefix}-datacenter-cicd"
    Component = "datacenter"
    Purpose   = "cicd-deploy"
  }
}

# Access key surfaced via Terraform outputs; the CI/CD workflow stores it in
# the ai/service/account/develop secret after apply.
resource "aws_iam_access_key" "datacenter_cicd" {
  user = aws_iam_user.datacenter_cicd.name
}

# ---------------------------------------------------------------------------
# Policy 1 - Secrets Manager: read the ecs-services secret only.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "datacenter_cicd_secrets" {
  statement {
    sid    = "ReadEcsServicesSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [data.aws_secretsmanager_secret.rorr_ecs_services.arn]
  }
}

resource "aws_iam_policy" "datacenter_cicd_secrets" {
  name        = "${local.name_prefix}-datacenter-cicd-secrets"
  description = "Read the rorr/develop/ecs-services secret for the DataCenter CI/CD pipeline"
  policy      = data.aws_iam_policy_document.datacenter_cicd_secrets.json
}

# ---------------------------------------------------------------------------
# Policy 2 - ECR: push/pull to every develop RORR repository.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "datacenter_cicd_ecr" {
  # Auth token is account-wide (no resource-level support).
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Push/pull limited to the develop RORR repositories.
  statement {
    sid    = "EcrPushPull"
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
    resources = local.datacenter_cicd_ecr_repo_arns
  }
}

resource "aws_iam_policy" "datacenter_cicd_ecr" {
  name        = "${local.name_prefix}-datacenter-cicd-ecr"
  description = "Push and pull images to the develop RORR ECR repositories"
  policy      = data.aws_iam_policy_document.datacenter_cicd_ecr.json
}

# ---------------------------------------------------------------------------
# Policy 3 - CloudWatch Logs: create groups/streams and put events.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "datacenter_cicd_logs" {
  statement {
    sid    = "EcsLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:us-east-1:*:log-group:/ecs/rorr-develop-*"]
  }
}

resource "aws_iam_policy" "datacenter_cicd_logs" {
  name        = "${local.name_prefix}-datacenter-cicd-logs"
  description = "Create and write ECS CloudWatch log groups for the DataCenter CI/CD pipeline"
  policy      = data.aws_iam_policy_document.datacenter_cicd_logs.json
}

# ---------------------------------------------------------------------------
# Attach policies to the CI/CD user.
# ---------------------------------------------------------------------------
resource "aws_iam_user_policy_attachment" "datacenter_cicd_secrets" {
  user       = aws_iam_user.datacenter_cicd.name
  policy_arn = aws_iam_policy.datacenter_cicd_secrets.arn
}

resource "aws_iam_user_policy_attachment" "datacenter_cicd_ecr" {
  user       = aws_iam_user.datacenter_cicd.name
  policy_arn = aws_iam_policy.datacenter_cicd_ecr.arn
}

resource "aws_iam_user_policy_attachment" "datacenter_cicd_logs" {
  user       = aws_iam_user.datacenter_cicd.name
  policy_arn = aws_iam_policy.datacenter_cicd_logs.arn
}
