# ---------------------------------------------------------------------------
# Dedicated IAM user for the DataCenter CI/CD deploy pipeline.
#
# This user lets GitHub Actions (or any external CI/CD runner) build and push
# the RORR develop Docker images and roll them out across the 8 LOL backend
# Fargate services. Least privilege only.
#
# Referencing rule:
#   * The ecs-services secret is created OUT OF BAND (MCP server prerequisite),
#     so it is pulled in with a data source (never managed here).
#   * The ECR repositories, ECS services and task/execution roles are all
#     managed in THIS same Terraform state. They are therefore referenced
#     directly (aws_ecr_repository.* / aws_ecs_service.* / aws_iam_role.*),
#     exactly as the sibling backend CI/CD user does in backend_iam_cicd.tf.
#     Direct references keep the ARNs in lock-step with the resources and avoid
#     the refresh-ordering pitfalls of data-sourcing same-state resources. The
#     "do not recreate these resources" intent is fully honoured.
# ---------------------------------------------------------------------------

locals {
  # LOL backend service ARNs (UpdateService / DescribeServices targets).
  # Built from the cluster name + exact service names, mirroring the existing
  # local.lol_collector_service_arn pattern in lol_backend_iam.tf.
  #
  # The dynamic list covers every member of local.lol_modules (incl.
  # rorr-lol-object-relay). rorr-lol-object-simulator is a standalone resource
  # (aws_ecs_service.object_simulator), so it is NOT part of local.lol_modules
  # and must be appended explicitly. It runs on the same backend cluster, so
  # the .id reference yields the correct service ARN.
  datacenter_cicd_service_arns = concat(
    [
      for name in local.lol_modules :
      "arn:aws:ecs:${local.region_id}:${local.account_id}:service/${local.lol_cluster_name}/${name}"
    ],
    [aws_ecs_service.object_simulator.id],
  )

  # Task definition ARNs (any revision) for the services above. RunTask is
  # scoped to these. family == service name (see aws_ecs_task_definition.lol).
  # object-simulator is appended via its family + ":*" so any revision the
  # CI/CD pipeline registers is covered, matching the backend_iam_cicd.tf
  # RunTask convention (never a single pinned .arn revision).
  datacenter_cicd_task_definition_arns = concat(
    [
      for name in local.lol_modules :
      "arn:aws:ecs:${local.region_id}:${local.account_id}:task-definition/${name}:*"
    ],
    ["arn:aws:ecs:${local.region_id}:${local.account_id}:task-definition/${aws_ecs_task_definition.object_simulator.family}:*"],
  )

  # All develop RORR ECR repositories the pipeline pushes/pulls.
  datacenter_cicd_ecr_repo_arns = [
    aws_ecr_repository.backend.arn,
    aws_ecr_repository.lol_backend.arn,
  ]

  # Execution role + every per-module task role, for the iam:PassRole grant.
  datacenter_cicd_passable_role_arns = concat(
    [aws_iam_role.rorr_lol_execution_role.arn],
    [for r in local.rorr_lol_task_roles : r.arn],
  )
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
# Policy 3 - ECS: deploy and run tasks across the 8 LOL backend services.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "datacenter_cicd_ecs" {
  # Task definition lifecycle actions do not support resource-level
  # permissions; they must be granted on "*".
  statement {
    sid    = "TaskDefinitions"
    effect = "Allow"
    actions = [
      "ecs:RegisterTaskDefinition",
      "ecs:DeregisterTaskDefinition",
      "ecs:DescribeTaskDefinition",
      "ecs:ListTaskDefinitions",
    ]
    resources = ["*"]
  }

  # Update / describe the 8 LOL backend services.
  statement {
    sid    = "DeployServices"
    effect = "Allow"
    actions = [
      "ecs:UpdateService",
      "ecs:DescribeServices",
    ]
    resources = local.datacenter_cicd_service_arns
  }

  # ListServices has no resource-level support; scope it to the backend cluster.
  statement {
    sid       = "ListServices"
    effect    = "Allow"
    actions   = ["ecs:ListServices"]
    resources = ["*"]
    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [aws_ecs_cluster.backend.arn]
    }
  }

  # Stop / list / describe tasks, scoped to the backend cluster via condition.
  statement {
    sid    = "TaskRuntime"
    effect = "Allow"
    actions = [
      "ecs:StopTask",
      "ecs:DescribeTasks",
      "ecs:ListTasks",
    ]
    resources = ["*"]
    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [aws_ecs_cluster.backend.arn]
    }
  }

  # Run a one-off task from any revision of the 8 task definitions, limited to
  # the backend cluster.
  statement {
    sid       = "RunTask"
    effect    = "Allow"
    actions   = ["ecs:RunTask"]
    resources = local.datacenter_cicd_task_definition_arns
    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [aws_ecs_cluster.backend.arn]
    }
  }

  # PassRole limited to the shared execution role + the 8 per-module task roles,
  # and only to the ECS tasks service.
  statement {
    sid       = "PassEcsRoles"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = local.datacenter_cicd_passable_role_arns
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "datacenter_cicd_ecs" {
  name        = "${local.name_prefix}-datacenter-cicd-ecs"
  description = "Deploy and run tasks across the 8 LOL backend ECS services"
  policy      = data.aws_iam_policy_document.datacenter_cicd_ecs.json
}

# ---------------------------------------------------------------------------
# Policy 4 - CloudWatch Logs: create groups/streams and put events.
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
# Attach all four policies to the CI/CD user.
# ---------------------------------------------------------------------------
resource "aws_iam_user_policy_attachment" "datacenter_cicd_secrets" {
  user       = aws_iam_user.datacenter_cicd.name
  policy_arn = aws_iam_policy.datacenter_cicd_secrets.arn
}

resource "aws_iam_user_policy_attachment" "datacenter_cicd_ecr" {
  user       = aws_iam_user.datacenter_cicd.name
  policy_arn = aws_iam_policy.datacenter_cicd_ecr.arn
}

resource "aws_iam_user_policy_attachment" "datacenter_cicd_ecs" {
  user       = aws_iam_user.datacenter_cicd.name
  policy_arn = aws_iam_policy.datacenter_cicd_ecs.arn
}

resource "aws_iam_user_policy_attachment" "datacenter_cicd_logs" {
  user       = aws_iam_user.datacenter_cicd.name
  policy_arn = aws_iam_policy.datacenter_cicd_logs.arn
}
