# ---------------------------------------------------------------------------
# LOL backend pipeline IAM: one shared execution role + one task role per
# module (least privilege, scoped to the exact MSK cluster/topics it touches).
# ---------------------------------------------------------------------------
locals {
  # Helper: full MSK topic ARN for an IAM resource.
  lol_topic_arns = {
    live_games = "${local.msk_topic_arn_prefix}/rorr-lol-live-games"
    raw        = "${local.msk_topic_arn_prefix}/rorr-lol-raw"
    processed  = "${local.msk_topic_arn_prefix}/rorr-lol-processed"
    context    = "${local.msk_topic_arn_prefix}/rorr-lol-context"
  }

  # Log group ARN per module (scopes the logs:* / logs:Create* grants).
  lol_log_group_arns = {
    for name in local.lol_modules :
    name => "arn:aws:logs:${local.region_id}:${local.account_id}:log-group:/ecs/${name}:*"
  }

  # ECS service ARN of the self-scaling collector (UpdateService target).
  lol_collector_service_arn = "arn:aws:ecs:${local.region_id}:${local.account_id}:service/${local.lol_cluster_name}/rorr-lol-collector"

  # Module service name -> task role object. Lets the ECS task definitions and
  # the OIDC deploy PassRole list reference the per-module roles by service name
  # without repeating the explicit resource addresses.
  rorr_lol_task_roles = {
    "rorr-lol-collector"           = aws_iam_role.rorr_lol_collector_task_role
    "rorr-lol-raw-store"           = aws_iam_role.rorr_lol_raw_store_task_role
    "rorr-lol-processor"           = aws_iam_role.rorr_lol_processor_task_role
    "rorr-lol-processed-store"     = aws_iam_role.rorr_lol_processed_store_task_role
    "rorr-lol-contextualizer"      = aws_iam_role.rorr_lol_contextualizer_task_role
    "rorr-lol-processed-deliverer" = aws_iam_role.rorr_lol_processed_deliverer_task_role
    "rorr-lol-context-store"       = aws_iam_role.rorr_lol_context_store_task_role
    "rorr-lol-context-deliverer"   = aws_iam_role.rorr_lol_context_deliverer_task_role
    "rorr-lol-meta-collector"      = aws_iam_role.rorr_lol_meta_collector_task_role
  }
}

# Existing secret holding the LOL backend ECS service ARNs + ECR repo URI.
# Created out-of-band by the MCP server; referenced here (never managed).
data "aws_secretsmanager_secret" "rorr_lol_ecs_services" {
  name = "rorr/develop/ecs-services"
}

# Per-concern application secrets, created out-of-band by the MCP server and
# referenced here (never managed). Each task role is granted GetSecretValue
# only on the secrets it actually reads at runtime (least privilege).
data "aws_secretsmanager_secret" "rorr_lol_database" {
  name = "rorr/develop/database"
}

data "aws_secretsmanager_secret" "rorr_lol_riot" {
  name = "rorr/develop/riot"
}

data "aws_secretsmanager_secret" "rorr_lol_kafka" {
  name = "rorr/develop/kafka"
}

data "aws_secretsmanager_secret" "rorr_lol_redis" {
  name = "rorr/develop/redis"
}

# ---------------------------------------------------------------------------
# Shared execution role: pull image from ECR, write logs, inject the rorr
# secret. (reuses the existing ecs-tasks assume policy and rorr_secret_read.)
# ---------------------------------------------------------------------------
resource "aws_iam_role" "rorr_lol_execution_role" {
  name               = "rorr-lol-execution-role"
  assume_role_policy = data.aws_iam_policy_document.backend_ecs_assume.json

  tags = {
    Name      = "rorr-lol-execution-role"
    Component = "lol-backend"
  }
}

resource "aws_iam_role_policy_attachment" "rorr_lol_execution_managed" {
  role       = aws_iam_role.rorr_lol_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# secretsmanager:GetSecretValue on the rorr secret (for secret injection).
resource "aws_iam_role_policy_attachment" "rorr_lol_execution_secret" {
  role       = aws_iam_role.rorr_lol_execution_role.name
  policy_arn = aws_iam_policy.rorr_secret_read.arn
}

# ---------------------------------------------------------------------------
# Module task roles (one per service, name = <service>-task-role).
# ---------------------------------------------------------------------------
resource "aws_iam_role" "rorr_lol_collector_task_role" {
  name               = "rorr-lol-collector-task-role"
  assume_role_policy = data.aws_iam_policy_document.backend_ecs_assume.json

  tags = {
    Name      = "rorr-lol-collector-task-role"
    Component = "lol-backend"
  }
}

resource "aws_iam_role" "rorr_lol_raw_store_task_role" {
  name               = "rorr-lol-raw-store-task-role"
  assume_role_policy = data.aws_iam_policy_document.backend_ecs_assume.json

  tags = {
    Name      = "rorr-lol-raw-store-task-role"
    Component = "lol-backend"
  }
}

resource "aws_iam_role" "rorr_lol_processor_task_role" {
  name               = "rorr-lol-processor-task-role"
  assume_role_policy = data.aws_iam_policy_document.backend_ecs_assume.json

  tags = {
    Name      = "rorr-lol-processor-task-role"
    Component = "lol-backend"
  }
}

resource "aws_iam_role" "rorr_lol_processed_store_task_role" {
  name               = "rorr-lol-processed-store-task-role"
  assume_role_policy = data.aws_iam_policy_document.backend_ecs_assume.json

  tags = {
    Name      = "rorr-lol-processed-store-task-role"
    Component = "lol-backend"
  }
}

resource "aws_iam_role" "rorr_lol_contextualizer_task_role" {
  name               = "rorr-lol-contextualizer-task-role"
  assume_role_policy = data.aws_iam_policy_document.backend_ecs_assume.json

  tags = {
    Name      = "rorr-lol-contextualizer-task-role"
    Component = "lol-backend"
  }
}

resource "aws_iam_role" "rorr_lol_processed_deliverer_task_role" {
  name               = "rorr-lol-processed-deliverer-task-role"
  assume_role_policy = data.aws_iam_policy_document.backend_ecs_assume.json

  tags = {
    Name      = "rorr-lol-processed-deliverer-task-role"
    Component = "lol-backend"
  }
}

resource "aws_iam_role" "rorr_lol_context_store_task_role" {
  name               = "rorr-lol-context-store-task-role"
  assume_role_policy = data.aws_iam_policy_document.backend_ecs_assume.json

  tags = {
    Name      = "rorr-lol-context-store-task-role"
    Component = "lol-backend"
  }
}

resource "aws_iam_role" "rorr_lol_context_deliverer_task_role" {
  name               = "rorr-lol-context-deliverer-task-role"
  assume_role_policy = data.aws_iam_policy_document.backend_ecs_assume.json

  tags = {
    Name      = "rorr-lol-context-deliverer-task-role"
    Component = "lol-backend"
  }
}

resource "aws_iam_role" "rorr_lol_meta_collector_task_role" {
  name               = "rorr-lol-meta-collector-task-role"
  assume_role_policy = data.aws_iam_policy_document.backend_ecs_assume.json

  tags = {
    Name      = "rorr-lol-meta-collector-task-role"
    Component = "lol-backend"
  }
}

# Every module reads the rorr secret at runtime (database/riot/redis/kafka keys).
resource "aws_iam_role_policy_attachment" "rorr_lol_task_secret" {
  for_each = local.rorr_lol_task_roles

  role       = each.value.name
  policy_arn = aws_iam_policy.rorr_secret_read.arn
}

# --- rorr-lol-collector -----------------------------------------------------
data "aws_iam_policy_document" "rorr_lol_collector" {
  statement {
    sid       = "MskConnect"
    effect    = "Allow"
    actions   = ["kafka-cluster:Connect", "kafka-cluster:AlterCluster", "kafka-cluster:WriteDataIdempotently", "kafka-cluster:CreateTopic"]
    resources = [aws_msk_cluster.main.arn]
  }
  statement {
    sid       = "Topics"
    effect    = "Allow"
    actions   = ["kafka-cluster:CreateTopic", "kafka-cluster:DescribeTopic", "kafka-cluster:WriteData", "kafka-cluster:WriteDataIdempotently", "kafka-cluster:ReadData"]
    resources = ["${local.msk_topic_arn_prefix}/*"]
  }
  statement {
    sid       = "SelfScale"
    effect    = "Allow"
    actions   = ["ecs:UpdateService", "ecs:DescribeServices"]
    resources = [local.lol_collector_service_arn]
  }
  statement {
    sid       = "ConsumerGroup"
    effect    = "Allow"
    actions   = ["kafka-cluster:AlterGroup", "kafka-cluster:DescribeGroup"]
    resources = ["${local.msk_group_arn_prefix}/*"]
  }
  statement {
    sid       = "Logs"
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [local.lol_log_group_arns["rorr-lol-collector"]]
  }
  statement {
    sid       = "EcsServicesSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [data.aws_secretsmanager_secret.rorr_lol_ecs_services.arn]
  }
  statement {
    sid     = "AppSecrets"
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      data.aws_secretsmanager_secret.rorr_lol_database.arn,
      data.aws_secretsmanager_secret.rorr_lol_riot.arn,
      data.aws_secretsmanager_secret.rorr_lol_redis.arn,
      data.aws_secretsmanager_secret.rorr_lol_kafka.arn,
    ]
  }
}

resource "aws_iam_role_policy" "rorr_lol_collector_task_policy" {
  name   = "rorr-lol-collector-task-policy"
  role   = aws_iam_role.rorr_lol_collector_task_role.id
  policy = data.aws_iam_policy_document.rorr_lol_collector.json
}

# --- rorr-lol-raw-store -----------------------------------------------------
data "aws_iam_policy_document" "rorr_lol_raw_store" {
  statement {
    sid       = "MskConnect"
    effect    = "Allow"
    actions   = ["kafka-cluster:Connect", "kafka-cluster:WriteDataIdempotently", "kafka-cluster:CreateTopic"]
    resources = [aws_msk_cluster.main.arn]
  }
  statement {
    sid       = "TopicRaw"
    effect    = "Allow"
    actions   = ["kafka-cluster:CreateTopic", "kafka-cluster:DescribeTopic", "kafka-cluster:ReadData"]
    resources = ["${local.msk_topic_arn_prefix}/*"]
  }
  statement {
    sid       = "Logs"
    effect    = "Allow"
    actions   = ["logs:*"]
    resources = [local.lol_log_group_arns["rorr-lol-raw-store"]]
  }
  statement {
    sid       = "ConsumerGroup"
    effect    = "Allow"
    actions   = ["kafka-cluster:AlterGroup", "kafka-cluster:DescribeGroup"]
    resources = ["${local.msk_group_arn_prefix}/*"]
  }
  statement {
    sid       = "EcsServicesSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [data.aws_secretsmanager_secret.rorr_lol_ecs_services.arn]
  }
  statement {
    sid     = "AppSecrets"
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      data.aws_secretsmanager_secret.rorr_lol_database.arn,
      data.aws_secretsmanager_secret.rorr_lol_kafka.arn,
    ]
  }
}

resource "aws_iam_role_policy" "rorr_lol_raw_store_task_policy" {
  name   = "rorr-lol-raw-store-task-policy"
  role   = aws_iam_role.rorr_lol_raw_store_task_role.id
  policy = data.aws_iam_policy_document.rorr_lol_raw_store.json
}

# --- rorr-lol-processor -----------------------------------------------------
data "aws_iam_policy_document" "rorr_lol_processor" {
  statement {
    sid       = "MskConnect"
    effect    = "Allow"
    actions   = ["kafka-cluster:Connect", "kafka-cluster:WriteDataIdempotently", "kafka-cluster:CreateTopic"]
    resources = [aws_msk_cluster.main.arn]
  }
  statement {
    sid       = "TopicRawRead"
    effect    = "Allow"
    actions   = ["kafka-cluster:CreateTopic", "kafka-cluster:DescribeTopic", "kafka-cluster:ReadData"]
    resources = ["${local.msk_topic_arn_prefix}/*"]
  }
  statement {
    sid       = "TopicProcessedWrite"
    effect    = "Allow"
    actions   = ["kafka-cluster:CreateTopic", "kafka-cluster:DescribeTopic", "kafka-cluster:WriteData", "kafka-cluster:WriteDataIdempotently"]
    resources = ["${local.msk_topic_arn_prefix}/*"]
  }
  statement {
    sid       = "Logs"
    effect    = "Allow"
    actions   = ["logs:*"]
    resources = [local.lol_log_group_arns["rorr-lol-processor"]]
  }
  statement {
    sid       = "ConsumerGroup"
    effect    = "Allow"
    actions   = ["kafka-cluster:AlterGroup", "kafka-cluster:DescribeGroup"]
    resources = ["${local.msk_group_arn_prefix}/*"]
  }
  statement {
    sid       = "EcsServicesSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [data.aws_secretsmanager_secret.rorr_lol_ecs_services.arn]
  }
  statement {
    sid       = "AppSecrets"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [data.aws_secretsmanager_secret.rorr_lol_kafka.arn]
  }
}

resource "aws_iam_role_policy" "rorr_lol_processor_task_policy" {
  name   = "rorr-lol-processor-task-policy"
  role   = aws_iam_role.rorr_lol_processor_task_role.id
  policy = data.aws_iam_policy_document.rorr_lol_processor.json
}

# --- rorr-lol-processed-store -----------------------------------------------
data "aws_iam_policy_document" "rorr_lol_processed_store" {
  statement {
    sid       = "MskConnect"
    effect    = "Allow"
    actions   = ["kafka-cluster:Connect", "kafka-cluster:WriteDataIdempotently", "kafka-cluster:CreateTopic"]
    resources = [aws_msk_cluster.main.arn]
  }
  statement {
    sid       = "TopicProcessedRead"
    effect    = "Allow"
    actions   = ["kafka-cluster:CreateTopic", "kafka-cluster:DescribeTopic", "kafka-cluster:ReadData"]
    resources = ["${local.msk_topic_arn_prefix}/*"]
  }
  statement {
    sid       = "Logs"
    effect    = "Allow"
    actions   = ["logs:*"]
    resources = [local.lol_log_group_arns["rorr-lol-processed-store"]]
  }
  statement {
    sid       = "ConsumerGroup"
    effect    = "Allow"
    actions   = ["kafka-cluster:AlterGroup", "kafka-cluster:DescribeGroup"]
    resources = ["${local.msk_group_arn_prefix}/*"]
  }
  statement {
    sid       = "EcsServicesSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [data.aws_secretsmanager_secret.rorr_lol_ecs_services.arn]
  }
  statement {
    sid     = "AppSecrets"
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      data.aws_secretsmanager_secret.rorr_lol_database.arn,
      data.aws_secretsmanager_secret.rorr_lol_kafka.arn,
    ]
  }
}

resource "aws_iam_role_policy" "rorr_lol_processed_store_task_policy" {
  name   = "rorr-lol-processed-store-task-policy"
  role   = aws_iam_role.rorr_lol_processed_store_task_role.id
  policy = data.aws_iam_policy_document.rorr_lol_processed_store.json
}

# --- rorr-lol-contextualizer ------------------------------------------------
data "aws_iam_policy_document" "rorr_lol_contextualizer" {
  statement {
    sid       = "MskConnect"
    effect    = "Allow"
    actions   = ["kafka-cluster:Connect", "kafka-cluster:WriteDataIdempotently", "kafka-cluster:CreateTopic"]
    resources = [aws_msk_cluster.main.arn]
  }
  statement {
    sid       = "TopicProcessedRead"
    effect    = "Allow"
    actions   = ["kafka-cluster:CreateTopic", "kafka-cluster:DescribeTopic", "kafka-cluster:ReadData"]
    resources = ["${local.msk_topic_arn_prefix}/*"]
  }
  statement {
    sid       = "TopicContextWrite"
    effect    = "Allow"
    actions   = ["kafka-cluster:CreateTopic", "kafka-cluster:DescribeTopic", "kafka-cluster:WriteData", "kafka-cluster:WriteDataIdempotently"]
    resources = ["${local.msk_topic_arn_prefix}/*"]
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
  statement {
    sid       = "ConsumerGroup"
    effect    = "Allow"
    actions   = ["kafka-cluster:AlterGroup", "kafka-cluster:DescribeGroup"]
    resources = ["${local.msk_group_arn_prefix}/*"]
  }
  statement {
    sid       = "EcsServicesSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [data.aws_secretsmanager_secret.rorr_lol_ecs_services.arn]
  }
  statement {
    sid     = "AppSecrets"
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      data.aws_secretsmanager_secret.rorr_lol_database.arn,
      data.aws_secretsmanager_secret.rorr_lol_kafka.arn,
    ]
  }
}

resource "aws_iam_role_policy" "rorr_lol_contextualizer_task_policy" {
  name   = "rorr-lol-contextualizer-task-policy"
  role   = aws_iam_role.rorr_lol_contextualizer_task_role.id
  policy = data.aws_iam_policy_document.rorr_lol_contextualizer.json
}

# --- rorr-lol-processed-deliverer -------------------------------------------
data "aws_iam_policy_document" "rorr_lol_processed_deliverer" {
  statement {
    sid       = "MskConnect"
    effect    = "Allow"
    actions   = ["kafka-cluster:Connect", "kafka-cluster:WriteDataIdempotently", "kafka-cluster:CreateTopic"]
    resources = [aws_msk_cluster.main.arn]
  }
  statement {
    sid       = "TopicProcessedRead"
    effect    = "Allow"
    actions   = ["kafka-cluster:CreateTopic", "kafka-cluster:DescribeTopic", "kafka-cluster:ReadData"]
    resources = ["${local.msk_topic_arn_prefix}/*"]
  }
  statement {
    sid       = "Logs"
    effect    = "Allow"
    actions   = ["logs:*"]
    resources = [local.lol_log_group_arns["rorr-lol-processed-deliverer"]]
  }
  statement {
    sid       = "ConsumerGroup"
    effect    = "Allow"
    actions   = ["kafka-cluster:AlterGroup", "kafka-cluster:DescribeGroup"]
    resources = ["${local.msk_group_arn_prefix}/*"]
  }
  statement {
    sid       = "EcsServicesSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [data.aws_secretsmanager_secret.rorr_lol_ecs_services.arn]
  }
  statement {
    sid     = "AppSecrets"
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      data.aws_secretsmanager_secret.rorr_lol_kafka.arn,
      data.aws_secretsmanager_secret.rorr_lol_redis.arn,
    ]
  }
}

resource "aws_iam_role_policy" "rorr_lol_processed_deliverer_task_policy" {
  name   = "rorr-lol-processed-deliverer-task-policy"
  role   = aws_iam_role.rorr_lol_processed_deliverer_task_role.id
  policy = data.aws_iam_policy_document.rorr_lol_processed_deliverer.json
}

# --- rorr-lol-context-store -------------------------------------------------
data "aws_iam_policy_document" "rorr_lol_context_store" {
  statement {
    sid       = "MskConnect"
    effect    = "Allow"
    actions   = ["kafka-cluster:Connect", "kafka-cluster:WriteDataIdempotently", "kafka-cluster:CreateTopic"]
    resources = [aws_msk_cluster.main.arn]
  }
  statement {
    sid       = "TopicContextRead"
    effect    = "Allow"
    actions   = ["kafka-cluster:CreateTopic", "kafka-cluster:DescribeTopic", "kafka-cluster:ReadData"]
    resources = ["${local.msk_topic_arn_prefix}/*"]
  }
  statement {
    sid       = "Logs"
    effect    = "Allow"
    actions   = ["logs:*"]
    resources = [local.lol_log_group_arns["rorr-lol-context-store"]]
  }
  statement {
    sid       = "ConsumerGroup"
    effect    = "Allow"
    actions   = ["kafka-cluster:AlterGroup", "kafka-cluster:DescribeGroup"]
    resources = ["${local.msk_group_arn_prefix}/*"]
  }
  statement {
    sid       = "EcsServicesSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [data.aws_secretsmanager_secret.rorr_lol_ecs_services.arn]
  }
  statement {
    sid     = "AppSecrets"
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      data.aws_secretsmanager_secret.rorr_lol_database.arn,
      data.aws_secretsmanager_secret.rorr_lol_kafka.arn,
    ]
  }
}

resource "aws_iam_role_policy" "rorr_lol_context_store_task_policy" {
  name   = "rorr-lol-context-store-task-policy"
  role   = aws_iam_role.rorr_lol_context_store_task_role.id
  policy = data.aws_iam_policy_document.rorr_lol_context_store.json
}

# --- rorr-lol-context-deliverer ---------------------------------------------
data "aws_iam_policy_document" "rorr_lol_context_deliverer" {
  statement {
    sid       = "MskConnect"
    effect    = "Allow"
    actions   = ["kafka-cluster:Connect", "kafka-cluster:WriteDataIdempotently", "kafka-cluster:CreateTopic"]
    resources = [aws_msk_cluster.main.arn]
  }
  statement {
    sid       = "TopicContextRead"
    effect    = "Allow"
    actions   = ["kafka-cluster:CreateTopic", "kafka-cluster:DescribeTopic", "kafka-cluster:ReadData"]
    resources = ["${local.msk_topic_arn_prefix}/*"]
  }
  statement {
    sid       = "Logs"
    effect    = "Allow"
    actions   = ["logs:*"]
    resources = [local.lol_log_group_arns["rorr-lol-context-deliverer"]]
  }
  statement {
    sid       = "ConsumerGroup"
    effect    = "Allow"
    actions   = ["kafka-cluster:AlterGroup", "kafka-cluster:DescribeGroup"]
    resources = ["${local.msk_group_arn_prefix}/*"]
  }
  statement {
    sid       = "EcsServicesSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [data.aws_secretsmanager_secret.rorr_lol_ecs_services.arn]
  }
  statement {
    sid     = "AppSecrets"
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      data.aws_secretsmanager_secret.rorr_lol_kafka.arn,
      data.aws_secretsmanager_secret.rorr_lol_redis.arn,
    ]
  }
}

resource "aws_iam_role_policy" "rorr_lol_context_deliverer_task_policy" {
  name   = "rorr-lol-context-deliverer-task-policy"
  role   = aws_iam_role.rorr_lol_context_deliverer_task_role.id
  policy = data.aws_iam_policy_document.rorr_lol_context_deliverer.json
}

# --- rorr-lol-meta-collector ------------------------------------------------
# Meta collector pulls LoL meta from the Riot API and caches it in Redis,
# persisting to the database. It does NOT use Kafka/MSK and does NOT call
# Bedrock, so no kafka-cluster:* / bedrock:* grants. Reads the riot secret
# (rorr/develop/riot) and the rorr secret (ai/rorr/develop, holding database +
# redis) inline. ai/rorr/develop is also granted to every module via the shared
# rorr_secret_read attachment (aws_iam_role_policy_attachment.rorr_lol_task_secret).
data "aws_iam_policy_document" "rorr_lol_meta_collector" {
  statement {
    sid       = "Logs"
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [local.lol_log_group_arns["rorr-lol-meta-collector"]]
  }
  statement {
    sid     = "AppSecrets"
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      data.aws_secretsmanager_secret.rorr.arn,
      data.aws_secretsmanager_secret.rorr_lol_riot.arn,
    ]
  }
}

resource "aws_iam_role_policy" "rorr_lol_meta_collector_task_policy" {
  name   = "rorr-lol-meta-collector-task-policy"
  role   = aws_iam_role.rorr_lol_meta_collector_task_role.id
  policy = data.aws_iam_policy_document.rorr_lol_meta_collector.json
}
