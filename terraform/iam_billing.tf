# ---------------------------------------------------------------------------
# Dedicated IAM user "billing" for human billing administration via the AWS
# console. Console login only (no programmatic access key): this user manages
# the Billing console end to end -- viewing costs, creating/editing budgets,
# managing payment methods, invoices, tax settings, etc. Permissions come from
# the AWS managed "Billing" job-function policy (view + manage), which covers
# billing/ce/budgets/payments/invoicing/tax/freetier/consolidatedbilling. No MFA
# is enforced by policy. The initial console password is exposed only as a
# sensitive Terraform output and is never stored in code or committed.
# ---------------------------------------------------------------------------

resource "aws_iam_user" "billing" {
  name = "${local.name_prefix}-billing"
  path = "/billing/"

  tags = {
    Name      = "${local.name_prefix}-billing"
    Component = "billing"
    Purpose   = "billing-console-administration"
  }
}

# Console login. No PGP key, so the generated password is available as a
# Terraform attribute and surfaced through a sensitive output below. The user
# must change the password on first sign-in.
resource "aws_iam_user_login_profile" "billing" {
  user                    = aws_iam_user.billing.name
  password_length         = 20
  password_reset_required = true

  lifecycle {
    # Do not churn the password on every apply once it has been set.
    ignore_changes = [password_length, password_reset_required]
  }
}

# ---------------------------------------------------------------------------
# Billing permissions. Attach the AWS managed "Billing" job-function policy,
# which grants full billing-console access (view + manage): Cost Explorer,
# Budgets, payment methods, invoices, tax settings, Free Tier, and
# consolidated billing. This managed policy was confirmed to exist at
# arn:aws:iam::aws:policy/job-function/Billing.
# ---------------------------------------------------------------------------
resource "aws_iam_user_policy_attachment" "billing" {
  user       = aws_iam_user.billing.name
  policy_arn = "arn:aws:iam::aws:policy/job-function/Billing"
}

# ---------------------------------------------------------------------------
# Additional AWS managed policies for cost/savings/marketplace console tasks
# that the "Billing" job-function policy does not cover. Each is attached as a
# separate aws_iam_user_policy_attachment, mirroring the attachment above. All
# three managed policies were confirmed to exist via `aws iam get-policy`.
# ---------------------------------------------------------------------------

# Create and manage Savings Plans from the billing/cost console.
resource "aws_iam_user_policy_attachment" "billing_savings_plans" {
  user       = aws_iam_user.billing.name
  policy_arn = "arn:aws:iam::aws:policy/AWSSavingsPlansFullAccess"
}

# Administer the Cost Optimization Hub.
resource "aws_iam_user_policy_attachment" "billing_cost_optimization_hub" {
  user       = aws_iam_user.billing.name
  policy_arn = "arn:aws:iam::aws:policy/CostOptimizationHubAdminAccess"
}

# Manage AWS Marketplace subscriptions.
resource "aws_iam_user_policy_attachment" "billing_marketplace_subscriptions" {
  user       = aws_iam_user.billing.name
  policy_arn = "arn:aws:iam::aws:policy/AWSMarketplaceManageSubscriptions"
}

# ---------------------------------------------------------------------------
# Custom supplement policy for billing-console tasks that are not fully covered
# by the managed policies above: full read access to Cost Explorer, plus
# account contact/alternate-contact management and region opt-in controls.
# These are account/billing-level actions that do not support resource-level
# permissions, so Resource is "*". account:CloseAccount is deliberately
# excluded as too dangerous. No MFA condition is enforced (existing policy).
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "billing_console_supplement" {
  statement {
    sid    = "CostExplorerReadOnly"
    effect = "Allow"
    actions = [
      "ce:Get*",
      "ce:List*",
      "ce:Describe*",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AccountContactAndRegionManagement"
    effect = "Allow"
    actions = [
      "account:GetContactInformation",
      "account:PutContactInformation",
      "account:GetAlternateContact",
      "account:PutAlternateContact",
      "account:DeleteAlternateContact",
      "account:GetRegionOptStatus",
      "account:ListRegions",
      "account:EnableRegion",
      "account:DisableRegion",
      "account:GetPrimaryEmail",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "billing_console_supplement" {
  name        = "${local.name_prefix}-billing-console-supplement"
  description = "Supplemental billing console permissions: Cost Explorer read, account contact and region opt-in management"
  policy      = data.aws_iam_policy_document.billing_console_supplement.json
}

resource "aws_iam_user_policy_attachment" "billing_console_supplement" {
  user       = aws_iam_user.billing.name
  policy_arn = aws_iam_policy.billing_console_supplement.arn
}

# ---------------------------------------------------------------------------
# Outputs. The console password is sensitive and never printed in plaintext to
# logs, code or commits; retrieve it with:
#   terraform output -raw billing_console_password
# ---------------------------------------------------------------------------
output "billing_user_name" {
  description = "IAM user name for billing console administration"
  value       = aws_iam_user.billing.name
}

output "billing_console_password" {
  description = "Initial console password for the billing IAM user (reset required on first sign-in)"
  value       = aws_iam_user_login_profile.billing.password
  sensitive   = true
}
