# ---------------------------------------------------------------------------
# Dedicated IAM user "woody" for human DB access via SSM port forwarding only.
# No direct DB credentials and no broad SSM access: woody may open an SSM
# StartSession port-forwarding tunnel to the main_db instance and manage only
# its own sessions. Programmatic (AWS CLI) and console access are both enabled;
# the access key and console password are stored in Secrets Manager.
# ---------------------------------------------------------------------------

resource "aws_iam_user" "woody" {
  name = "${local.name_prefix}-woody"
  path = "/db-access/"

  tags = {
    Name      = "${local.name_prefix}-woody"
    Component = "main_db"
    Purpose   = "ssm-port-forward-db-access"
  }
}

# Programmatic access key for the AWS CLI (used to start the SSM session).
resource "aws_iam_access_key" "woody" {
  user = aws_iam_user.woody.name
}

# Console login. The generated password is stored in Secrets Manager below;
# no PGP key, so the password is available as a Terraform attribute.
resource "aws_iam_user_login_profile" "woody" {
  user                    = aws_iam_user.woody.name
  password_length         = 20
  password_reset_required = false

  lifecycle {
    # Do not churn the password on every apply once it has been set.
    ignore_changes = [password_length, password_reset_required]
  }
}

# ---------------------------------------------------------------------------
# SSM port-forwarding-only policy.
#   - StartSession: only the main_db instance, and only the two port-forwarding
#     SSM documents.
#   - Terminate/Resume: only sessions owned by woody (aws:username condition via
#     the session resource ARN).
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "woody_ssm_port_forward" {
  statement {
    sid     = "StartPortForwardingSession"
    effect  = "Allow"
    actions = ["ssm:StartSession"]
    resources = [
      aws_instance.main_db.arn,
      "arn:aws:ssm:${local.region_id}::document/AWS-StartPortForwardingSession",
      "arn:aws:ssm:${local.region_id}::document/AWS-StartPortForwardingSessionToRemoteHost",
    ]
  }

  # Manage only woody's own sessions (session id is prefixed with the username).
  statement {
    sid    = "ManageOwnSessions"
    effect = "Allow"
    actions = [
      "ssm:TerminateSession",
      "ssm:ResumeSession",
    ]
    resources = [
      "arn:aws:ssm:*:${local.account_id}:session/$${aws:username}-*",
    ]
  }
}

resource "aws_iam_user_policy" "woody_ssm_port_forward" {
  name   = "${local.name_prefix}-woody-ssm-port-forward"
  user   = aws_iam_user.woody.name
  policy = data.aws_iam_policy_document.woody_ssm_port_forward.json
}

# ---------------------------------------------------------------------------
# Store woody's credentials and DB connection target in a dedicated secret.
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "woody_key" {
  name        = "ai/rorr-infra/${var.env}-woody-key"
  description = "Access key, console password and DB target for the woody DB-access IAM user"

  tags = {
    Name      = "ai/rorr-infra/${var.env}-woody-key"
    Component = "main_db"
    Purpose   = "db-access-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "woody_key" {
  secret_id = aws_secretsmanager_secret.woody_key.id
  secret_string = jsonencode({
    access_key_id     = aws_iam_access_key.woody.id
    secret_access_key = aws_iam_access_key.woody.secret
    console_password  = aws_iam_user_login_profile.woody.password
    db_host           = aws_instance.main_db.private_ip
    db_port           = tostring(var.backend_db_port)
  })
}

# ---------------------------------------------------------------------------
# Merge a "woody" group into the shared ai/rorr-infra/${env} secret after apply.
# Read-modify-write with jq so other top-level keys are preserved; this only
# adds/replaces the "woody" key. Runs during apply (CI/CD context).
# ---------------------------------------------------------------------------
resource "null_resource" "woody_secret" {
  triggers = {
    iam_user   = aws_iam_user.woody.name
    key_secret = aws_secretsmanager_secret.woody_key.name
    db_host    = aws_instance.main_db.private_ip
    db_port    = tostring(var.backend_db_port)
    secret_id  = data.aws_secretsmanager_secret.rorr_infra.id
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      GROUP=$(jq -n \
        --arg iamuser   "${aws_iam_user.woody.name}" \
        --arg keysecret "${aws_secretsmanager_secret.woody_key.name}" \
        --arg dbhost    "${aws_instance.main_db.private_ip}" \
        --arg dbport    "${var.backend_db_port}" \
        '{
          "woody": {
            iam_user:    $iamuser,
            secret_name: $keysecret,
            db: {
              host: $dbhost,
              port: $dbport
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
    aws_secretsmanager_secret_version.woody_key,
  ]
}

# ---------------------------------------------------------------------------
# Outputs.
# ---------------------------------------------------------------------------
output "woody_user_name" {
  description = "IAM user name for woody DB access"
  value       = aws_iam_user.woody.name
}

output "woody_key_secret_arn" {
  description = "ARN of the secret holding woody's access key and console password"
  value       = aws_secretsmanager_secret.woody_key.arn
}
