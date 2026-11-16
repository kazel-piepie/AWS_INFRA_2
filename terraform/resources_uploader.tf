# ---------------------------------------------------------------------------
# IAM user "${local.name_prefix}-resources-uploader".
#
# A human, console-only account (login profile; no access key) used to upload
# frontend resource files to the ${local.s3_name_prefix}-frontend-resources S3
# bucket (see frontend-resources.tf).
#
# develop: user was created out-of-band (AWS console, 2026-06-09) and is
#   adopted into Terraform via the import blocks below.
# prod: user does not exist yet; Terraform creates it on the next apply.
#
# Deliberately NOT managed here:
#   - aws_iam_user_login_profile: left out-of-band to avoid a forced password
#     reset on the already-active develop account; set manually after first apply
#     for prod.
#   - aws_iam_access_key: this user needs no programmatic access key.
#
# Environment gating: active only in develop and prod. staging is excluded
# because there is no corresponding human account there.
# Import gating: import blocks run only for develop (where the out-of-band user
# exists); prod creates a fresh user, so no import is needed.
# ---------------------------------------------------------------------------

locals {
  # Non-empty in develop and prod; empty in staging.
  resources_uploader_envs = contains(["develop", "prod"], var.env) ? toset([var.env]) : toset([])

  # Import only applies to develop, where the user was created out-of-band.
  # prod creates a new user, so no import block is needed there.
  resources_uploader_import_envs = var.env == "develop" ? toset(["develop"]) : toset([])
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
    resources = [
      "arn:aws:s3:::${local.name_prefix}-frontend-resources/*",
      "arn:aws:s3:::${local.s3_name_prefix}-frontend-resources/*",
    ]
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
    resources = [
      "arn:aws:s3:::${local.name_prefix}-frontend-resources",
      "arn:aws:s3:::${local.s3_name_prefix}-frontend-resources",
    ]
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
  for_each = local.resources_uploader_import_envs

  to = aws_iam_user.resources_uploader[each.key]
  id = "${local.name_prefix}-resources-uploader"
}

import {
  for_each = local.resources_uploader_import_envs

  to = aws_iam_user_policy.resources_uploader[each.key]
  id = "${local.name_prefix}-resources-uploader:${local.name_prefix}-resources-uploader-policy"
}
