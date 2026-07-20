# ---------------------------------------------------------------------------
# IAM user "ai-rorr-develop-resources-uploader".
#
# This user was created out-of-band (directly in the AWS console, 2026-06-09)
# and was never present in this repo's Terraform state. It is a human,
# console-only account (a login profile exists and is in active use; there is
# no programmatic access key) used to upload frontend resource files to the
# ai-rorr-develop-frontend-resources S3 bucket (see frontend-resources.tf).
#
# This file adopts the user into Terraform via `import` blocks (declared here;
# the actual state import runs on the next CI/CD apply after merge) and extends
# its single inline policy with full CloudFront access.
#
# Deliberately NOT managed here:
#   - aws_iam_user_login_profile: the console password is already set and the
#     account is actively used by a person. Importing/managing it risks a forced
#     password reset or state drift, so the login profile is left out-of-band.
#   - aws_iam_access_key: this user has no programmatic access key and needs none.
#
# Environment gating: the same Terraform code is applied to develop, staging and
# prod (each against its own AWS account). This user exists ONLY in the develop
# account, so both the resource and its import are gated to env == "develop";
# without the gate, staging/prod applies would fail importing a user that does
# not exist there.
# ---------------------------------------------------------------------------

locals {
  # Non-empty only in develop, where this out-of-band user actually exists.
  resources_uploader_envs = var.env == "develop" ? toset(["develop"]) : toset([])
}

# ---------------------------------------------------------------------------
# The IAM user. name/path/tags mirror the live resource exactly. The live tags
# are Project=ai-rorr, Environment=develop, Purpose=frontend-resources-upload;
# Project and Environment are supplied by the provider default_tags (identical
# values), so only Purpose is declared here — matching the repo convention (see
# iam_billing.tf / frontend.tf). On adoption the provider additionally adds
# ManagedBy=terraform, which the live out-of-band user does not yet carry.
# ---------------------------------------------------------------------------
resource "aws_iam_user" "resources_uploader" {
  for_each = local.resources_uploader_envs

  name = "${local.name_prefix}-resources-uploader"
  path = "/"

  tags = {
    Purpose = "frontend-resources-upload"
  }
}

# ---------------------------------------------------------------------------
# Inline policy ai-rorr-${env}-resources-uploader-policy. The first three
# statements are transcribed exactly from the live inline policy (unchanged);
# the fourth statement (CloudFrontFullAccess) is newly added by this change.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "resources_uploader" {
  # --- Existing (unchanged): object-level access to the resources bucket. ---
  statement {
    sid    = "FrontendResourcesObjectAccess"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:GetObjectAcl",
    ]
    resources = ["arn:aws:s3:::ai-rorr-develop-frontend-resources/*"]
  }

  # --- Existing (unchanged): bucket-level access to the resources bucket. ---
  statement {
    sid    = "FrontendResourcesBucketAccess"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:GetBucketPolicy",
      "s3:GetBucketAcl",
      "s3:GetBucketCORS",
      "s3:GetBucketVersioning",
    ]
    resources = ["arn:aws:s3:::ai-rorr-develop-frontend-resources"]
  }

  # --- Existing (unchanged): list all buckets (console navigation). ---
  statement {
    sid       = "ListAllBuckets"
    effect    = "Allow"
    actions   = ["s3:ListAllMyBuckets"]
    resources = ["*"]
  }

  # --- New: full CloudFront access. ---
  statement {
    sid       = "CloudFrontFullAccess"
    effect    = "Allow"
    actions   = ["cloudfront:*"]
    resources = ["*"]
  }
}

resource "aws_iam_user_policy" "resources_uploader" {
  for_each = local.resources_uploader_envs

  name   = "${local.name_prefix}-resources-uploader-policy"
  user   = aws_iam_user.resources_uploader[each.key].name
  policy = data.aws_iam_policy_document.resources_uploader.json
}

# ---------------------------------------------------------------------------
# Import blocks (declarative). These adopt the existing live resources into
# Terraform state; the actual import is performed by the next CI/CD apply after
# this PR merges. Once in state they are no-ops on subsequent plans.
#
#   aws_iam_user            import id: <user_name>
#   aws_iam_user_policy     import id: <user_name>:<policy_name>
# ---------------------------------------------------------------------------
import {
  for_each = local.resources_uploader_envs

  to = aws_iam_user.resources_uploader[each.key]
  id = "${local.name_prefix}-resources-uploader"
}

import {
  for_each = local.resources_uploader_envs

  to = aws_iam_user_policy.resources_uploader[each.key]
  id = "${local.name_prefix}-resources-uploader:${local.name_prefix}-resources-uploader-policy"
}
