# ---------------------------------------------------------------------------
# LOL backend pipeline IAM: one shared execution role + one task role per
# module (least privilege, scoped to the exact MSK cluster/topics it touches).
# ---------------------------------------------------------------------------
locals {
  # Helper: full MSK topic ARN for an IAM resource.
  lol_topic_arns = {
    live_games = "${local.msk_topic_arn_prefix}/live-games"
    raw        = "${local.msk_topic_arn_prefix}/raw"
    processed  = "${local.msk_topic_arn_prefix}/processed"
    context    = "${local.msk_topic_arn_prefix}/context"
  }

  # Log group ARN per module (scopes the logs:* / logs:Create* grants).
  lol_log_group_arns = {
    for name in local.lol_modules :
    name => "arn:aws:logs:${local.region_id}:${local.account_id}:log-group:/ecs/${name}:*"
  }

  # ECS service ARN of the self-scaling collector (UpdateService target).
  lol_collector_service_arn = "arn:aws:ecs:${local.region_id}:${local.account_id}:service/${local.lol_cluster_name}/rorr-lol-collector"
}

# ---------------------------------------------------------------------------
# Shared execution role: pull image from ECR, write logs, inject the rorr
# secret. (reuses the existing ecs-tasks assume policy and rorr_secret_read.)
# ---------------------------------------------------------------------------
resource "aws_iam_role" "lol_execution" {
  name               = "rorr-lol-execution-role"
  assume_role_policy = data.aws_iam_policy_document.backend_ecs_assume.json

  tags = {
    Name      = "rorr-lol-execution-role"
    Component = "lol-backend"
  }
}

resource "aws_iam_role_policy_attachment" "lol_execution_managed" {
  role       = aws_iam_role.lol_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# secretsmanager:GetSecretValue on the rorr secret (for secret injection).
resource "aws_iam_role_policy_attachment" "lol_execution_secret" {
  role       = aws_iam_role.lol_execution.name
  policy_arn = aws_iam_policy.rorr_secret_read.arn
}

# ---------------------------------------------------------------------------
# Module task roles (one per service, name = <service>-task-role).
# ---------------------------------------------------------------------------
resource "aws_iam_role" "lol_task" {
  for_each = local.lol_modules

  name               = "${each.value}-task-role"
  assume_role_policy = data.aws_iam_policy_document.backend_ecs_assume.json

  tags = {
    Name      = "${each.value}-task-role"
    Component = "lol-backend"
  }
}

# Every module reads the rorr secret at runtime (database/riot/redis/kafka keys).
resource "aws_iam_role_policy_attachment" "lol_task_secret" {
  for_each = local.lol_modules

  role       = aws_iam_role.lol_task[each.value].name
  policy_arn = aws_iam_policy.rorr_secret_read.arn
}

# --- rorr-lol-collector -----------------------------------------------------
data "aws_iam_policy_document" "lol_collector" {
  statement {
    sid       = "MskConnect"
    effect    = "Allow"
    actions   = ["kafka-cluster:Connect", "kafka-cluster:AlterCluster"]
    resources = [aws_msk_cluster.main.arn]
  }
  statement {
    sid       = "Topics"
    effect    = "Allow"
    actions   = ["kafka-cluster:CreateTopic", "kafka-cluster:DescribeTopic", "kafka-cluster:WriteData", "kafka-cluster:ReadData"]
    resources = [local.lol_topic_arns.live_games, local.lol_topic_arns.raw]
  }
  statement {
    sid       = "SelfScale"
    effect    = "Allow"
    actions   = ["ecs:UpdateService", "ecs:DescribeServices"]
    resources = [local.lol_collector_service_arn]
  }
  statement {
    sid       = "Logs"
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [local.lol_log_group_arns["rorr-lol-collector"]]
  }
}

resource "aws_iam_role_policy" "lol_collector" {
  name   = "rorr-lol-collector-task-policy"
  role   = aws_iam_role.lol_task["rorr-lol-collector"].id
  policy = data.aws_iam_policy_document.lol_collector.json
}

# --- rorr-lol-raw-store -----------------------------------------------------
data "aws_iam_policy_document" "lol_raw_store" {
  statement {
    sid       = "MskConnect"
    effect    = "Allow"
    actions   = ["kafka-cluster:Connect"]
    resources = [aws_msk_cluster.main.arn]
  }
  statement {
    sid       = "TopicRaw"
    effect    = "Allow"
    actions   = ["kafka-cluster:CreateTopic", "kafka-cluster:DescribeTopic", "kafka-cluster:ReadData"]
    resources = [local.lol_topic_arns.raw]
  }
  statement {
    sid       = "Logs"
    effect    = "Allow"
    actions   = ["logs:*"]
    resources = [local.lol_log_group_arns["rorr-lol-raw-store"]]
  }
}

resource "aws_iam_role_policy" "lol_raw_store" {
  name   = "rorr-lol-raw-store-task-policy"
  role   = aws_iam_role.lol_task["rorr-lol-raw-store"].id
  policy = data.aws_iam_policy_document.lol_raw_store.json
}

# --- rorr-lol-processor -----------------------------------------------------
data "aws_iam_policy_document" "lol_processor" {
  statement {
    sid       = "MskConnect"
    effect    = "Allow"
    actions   = ["kafka-cluster:Connect"]
    resources = [aws_msk_cluster.main.arn]
  }
  statement {
    sid       = "TopicRawRead"
    effect    = "Allow"
    actions   = ["kafka-cluster:CreateTopic", "kafka-cluster:DescribeTopic", "kafka-cluster:ReadData"]
    resources = [local.lol_topic_arns.raw]
  }
  statement {
    sid       = "TopicProcessedWrite"
    effect    = "Allow"
    actions   = ["kafka-cluster:CreateTopic", "kafka-cluster:DescribeTopic", "kafka-cluster:WriteData"]
    resources = [local.lol_topic_arns.processed]
  }
  statement {
    sid       = "Logs"
    effect    = "Allow"
    actions   = ["logs:*"]
    resources = [local.lol_log_group_arns["rorr-lol-processor"]]
  }
}

resource "aws_iam_role_policy" "lol_processor" {
  name   = "rorr-lol-processor-task-policy"
  role   = aws_iam_role.lol_task["rorr-lol-processor"].id
  policy = data.aws_iam_policy_document.lol_processor.json
}

# --- rorr-lol-processed-store -----------------------------------------------
data "aws_iam_policy_document" "lol_processed_store" {
  statement {
    sid       = "MskConnect"
    effect    = "Allow"
    actions   = ["kafka-cluster:Connect"]
    resources = [aws_msk_cluster.main.arn]
  }
  statement {
    sid       = "TopicProcessedRead"
    effect    = "Allow"
    actions   = ["kafka-cluster:CreateTopic", "kafka-cluster:DescribeTopic", "kafka-cluster:ReadData"]
    resources = [local.lol_topic_arns.processed]
  }
  statement {
    sid       = "Logs"
    effect    = "Allow"
    actions   = ["logs:*"]
    resources = [local.lol_log_group_arns["rorr-lol-processed-store"]]
  }
}

resource "aws_iam_role_policy" "lol_processed_store" {
  name   = "rorr-lol-processed-store-task-policy"
  role   = aws_iam_role.lol_task["rorr-lol-processed-store"].id
  policy = data.aws_iam_policy_document.lol_processed_store.json
}

# --- rorr-lol-contextualizer ------------------------------------------------
data "aws_iam_policy_document" "lol_contextualizer" {
  statement {
    sid       = "MskConnect"
    effect    = "Allow"
    actions   = ["kafka-cluster:Connect"]
    resources = [aws_msk_cluster.main.arn]
  }
  statement {
    sid       = "TopicProcessedRead"
    effect    = "Allow"
    actions   = ["kafka-cluster:CreateTopic", "kafka-cluster:DescribeTopic", "kafka-cluster:ReadData"]
    resources = [local.lol_topic_arns.processed]
  }
  statement {
    sid       = "TopicContextWrite"
    effect    = "Allow"
    actions   = ["kafka-cluster:CreateTopic", "kafka-cluster:DescribeTopic", "kafka-cluster:WriteData"]
    resources = [local.lol_topic_arns.context]
  }
  statement {
    sid       = "BedrockInvoke"
    effect    = "Allow"
    actions   = ["bedrock:InvokeModel"]
    resources = ["arn:aws:bedrock:${local.region_id}::foundation-model/*"]
  }
  statement {
    sid       = "Logs"
    effect    = "Allow"
    actions   = ["logs:*"]
    resources = [local.lol_log_group_arns["rorr-lol-contextualizer"]]
  }
}

resource "aws_iam_role_policy" "lol_contextualizer" {
  name   = "rorr-lol-contextualizer-task-policy"
  role   = aws_iam_role.lol_task["rorr-lol-contextualizer"].id
  policy = data.aws_iam_policy_document.lol_contextualizer.json
}

# --- rorr-lol-processed-deliverer -------------------------------------------
data "aws_iam_policy_document" "lol_processed_deliverer" {
  statement {
    sid       = "MskConnect"
    effect    = "Allow"
    actions   = ["kafka-cluster:Connect"]
    resources = [aws_msk_cluster.main.arn]
  }
  statement {
    sid       = "TopicProcessedRead"
    effect    = "Allow"
    actions   = ["kafka-cluster:CreateTopic", "kafka-cluster:DescribeTopic", "kafka-cluster:ReadData"]
    resources = [local.lol_topic_arns.processed]
  }
  statement {
    sid       = "Logs"
    effect    = "Allow"
    actions   = ["logs:*"]
    resources = [local.lol_log_group_arns["rorr-lol-processed-deliverer"]]
  }
}

resource "aws_iam_role_policy" "lol_processed_deliverer" {
  name   = "rorr-lol-processed-deliverer-task-policy"
  role   = aws_iam_role.lol_task["rorr-lol-processed-deliverer"].id
  policy = data.aws_iam_policy_document.lol_processed_deliverer.json
}

# --- rorr-lol-context-store -------------------------------------------------
data "aws_iam_policy_document" "lol_context_store" {
  statement {
    sid       = "MskConnect"
    effect    = "Allow"
    actions   = ["kafka-cluster:Connect"]
    resources = [aws_msk_cluster.main.arn]
  }
  statement {
    sid       = "TopicContextRead"
    effect    = "Allow"
    actions   = ["kafka-cluster:CreateTopic", "kafka-cluster:DescribeTopic", "kafka-cluster:ReadData"]
    resources = [local.lol_topic_arns.context]
  }
  statement {
    sid       = "Logs"
    effect    = "Allow"
    actions   = ["logs:*"]
    resources = [local.lol_log_group_arns["rorr-lol-context-store"]]
  }
}

resource "aws_iam_role_policy" "lol_context_store" {
  name   = "rorr-lol-context-store-task-policy"
  role   = aws_iam_role.lol_task["rorr-lol-context-store"].id
  policy = data.aws_iam_policy_document.lol_context_store.json
}

# --- rorr-lol-context-deliverer ---------------------------------------------
data "aws_iam_policy_document" "lol_context_deliverer" {
  statement {
    sid       = "MskConnect"
    effect    = "Allow"
    actions   = ["kafka-cluster:Connect"]
    resources = [aws_msk_cluster.main.arn]
  }
  statement {
    sid       = "TopicContextRead"
    effect    = "Allow"
    actions   = ["kafka-cluster:CreateTopic", "kafka-cluster:DescribeTopic", "kafka-cluster:ReadData"]
    resources = [local.lol_topic_arns.context]
  }
  statement {
    sid       = "Logs"
    effect    = "Allow"
    actions   = ["logs:*"]
    resources = [local.lol_log_group_arns["rorr-lol-context-deliverer"]]
  }
}

resource "aws_iam_role_policy" "lol_context_deliverer" {
  name   = "rorr-lol-context-deliverer-task-policy"
  role   = aws_iam_role.lol_task["rorr-lol-context-deliverer"].id
  policy = data.aws_iam_policy_document.lol_context_deliverer.json
}
