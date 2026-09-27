# ---------------------------------------------------------------------------
# RORR frontend *resources* infrastructure: a separate private S3 bucket for
# downloadable/static resource files, fronted by its own CloudFront
# distribution (Origin Access Control), served at ai-dev-resources.rorr.club.
#
# This is distinct from the main frontend website (see frontend.tf). The
# existing frontend CI/CD user (ai-rorr-${env}-frontend-cicd) is granted the
# extra S3/CloudFront permissions it needs to deploy here; those statements are
# merged into that user's single inline policy via `source_policy_documents`
# (see data.aws_iam_policy_document.frontend_cicd in frontend.tf) so there is
# still exactly one inline policy, ai-rorr-${env}-frontend-cicd-policy.
#
# Re-used data sources already declared in frontend.tf / data.tf:
#   data.aws_cloudfront_cache_policy.caching_optimized
#   data.aws_secretsmanager_secret.rorr_infra
#   data.aws_acm_certificate.rorr_club
# ---------------------------------------------------------------------------

locals {
  frontend_resources_bucket_name = "${local.name_prefix}-frontend-resources"
  frontend_resources_domain      = "ai-dev-resources.rorr.club"
}

# ---------------------------------------------------------------------------
# S3 bucket for resource files (private; reached only via CloudFront OAC).
# Versioning enabled; no website hosting (files are fetched directly by key).
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "frontend_resources" {
  bucket = local.frontend_resources_bucket_name

  tags = {
    Name      = local.frontend_resources_bucket_name
    Component = "frontend-resources"
    Purpose   = "static-resource-origin"
  }
}

# Block all public access; CloudFront OAC is the only allowed reader.
resource "aws_s3_bucket_public_access_block" "frontend_resources" {
  bucket = aws_s3_bucket.frontend_resources.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "frontend_resources" {
  bucket = aws_s3_bucket.frontend_resources.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Bucket policy: allow only this CloudFront distribution (via OAC) to read.
data "aws_iam_policy_document" "frontend_resources_bucket" {
  statement {
    sid    = "AllowCloudFrontOACRead"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.frontend_resources.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.frontend_resources.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend_resources" {
  bucket = aws_s3_bucket.frontend_resources.id
  policy = data.aws_iam_policy_document.frontend_resources_bucket.json

  # Public access block must settle before attaching a bucket policy.
  depends_on = [aws_s3_bucket_public_access_block.frontend_resources]
}

# ---------------------------------------------------------------------------
# CloudFront distribution fronting the private resources S3 bucket via OAC.
# HTTPS only (HTTP redirects to HTTPS); no default root object (direct keys);
# CachingOptimized managed cache policy.
# ---------------------------------------------------------------------------
resource "aws_cloudfront_origin_access_control" "frontend_resources" {
  name                              = "${local.name_prefix}-frontend-resources-oac"
  description                       = "OAC for the RORR frontend resources S3 origin"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "frontend_resources" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "RORR frontend resources distribution (${var.env})"
  aliases         = [local.frontend_resources_domain]
  price_class     = "PriceClass_100"

  # No default_root_object: resource files are addressed directly by key.

  origin {
    domain_name              = aws_s3_bucket.frontend_resources.bucket_regional_domain_name
    origin_id                = "s3-${local.frontend_resources_bucket_name}"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend_resources.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-${local.frontend_resources_bucket_name}"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = data.aws_acm_certificate.rorr_club.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    Name      = "${local.name_prefix}-frontend-resources"
    Component = "frontend-resources"
    Purpose   = "cdn"
  }
}

# ---------------------------------------------------------------------------
# Extra least-privilege statements added to the existing frontend CI/CD user's
# inline policy (ai-rorr-${env}-frontend-cicd-policy). Merged in frontend.tf
# via `source_policy_documents` so the user keeps a single inline policy.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "frontend_cicd_resources" {
  # --- S3: list the resources bucket. ---
  statement {
    sid    = "ListFrontendResourcesBucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [aws_s3_bucket.frontend_resources.arn]
  }

  # --- S3: read/write/delete objects in the resources bucket. ---
  statement {
    sid    = "DeployFrontendResourcesObjects"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:GetObject",
    ]
    resources = ["${aws_s3_bucket.frontend_resources.arn}/*"]
  }

  # --- CloudFront: invalidate the resources distribution cache. ---
  statement {
    sid       = "InvalidateFrontendResourcesCache"
    effect    = "Allow"
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [aws_cloudfront_distribution.frontend_resources.arn]
  }
}

# ---------------------------------------------------------------------------
# Persist the front-resources group into ai/rorr-infra/${env} after apply.
# Read-modify-write merge (jq) so other keys in the secret are preserved; this
# adds/replaces only the top-level "front-resources" key. Runs during apply
# (CI/CD context, which holds the deploy credentials).
# ---------------------------------------------------------------------------
resource "null_resource" "frontend_resources_secret" {
  triggers = {
    bucket           = aws_s3_bucket.frontend_resources.bucket
    distribution_id  = aws_cloudfront_distribution.frontend_resources.id
    domain_name      = aws_cloudfront_distribution.frontend_resources.domain_name
    distribution_arn = aws_cloudfront_distribution.frontend_resources.arn
    secret_id        = data.aws_secretsmanager_secret.rorr_infra.id
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      GROUP=$(jq -n \
        --arg bucket    "${aws_s3_bucket.frontend_resources.bucket}" \
        --arg region    "${var.region}" \
        --arg s3arn     "${aws_s3_bucket.frontend_resources.arn}" \
        --arg distid    "${aws_cloudfront_distribution.frontend_resources.id}" \
        --arg domain    "${aws_cloudfront_distribution.frontend_resources.domain_name}" \
        --arg distarn   "${aws_cloudfront_distribution.frontend_resources.arn}" \
        --arg alias     "${local.frontend_resources_domain}" \
        --arg status    "${aws_cloudfront_distribution.frontend_resources.status}" \
        --arg iamuser   "${aws_iam_user.frontend_cicd.name}" \
        --arg keysecret "${aws_secretsmanager_secret.frontend_cicd_key.name}" \
        '{
          "front-resources": {
            s3: {
              bucket_name: $bucket,
              region:      $region,
              arn:         $s3arn,
              versioning:  true
            },
            cloudfront: {
              distribution_id: $distid,
              domain_name:     $domain,
              arn:             $distarn,
              alias:           $alias,
              status:          $status
            },
            cicd: {
              iam_user:    $iamuser,
              secret_name: $keysecret
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
    aws_s3_bucket_versioning.frontend_resources,
    aws_cloudfront_distribution.frontend_resources,
  ]
}

# ---------------------------------------------------------------------------
# Outputs.
# ---------------------------------------------------------------------------
output "frontend_resources_bucket_name" {
  description = "Frontend resources S3 bucket name"
  value       = aws_s3_bucket.frontend_resources.bucket
}

output "frontend_resources_bucket_arn" {
  description = "Frontend resources S3 bucket ARN"
  value       = aws_s3_bucket.frontend_resources.arn
}

output "frontend_resources_cloudfront_domain_name" {
  description = "Resources CloudFront domain name (point ai-dev-resources.rorr.club at this)"
  value       = aws_cloudfront_distribution.frontend_resources.domain_name
}

output "frontend_resources_cloudfront_distribution_id" {
  description = "Resources CloudFront distribution id (for cache invalidations)"
  value       = aws_cloudfront_distribution.frontend_resources.id
}

output "frontend_resources_cloudfront_distribution_arn" {
  description = "Resources CloudFront distribution ARN"
  value       = aws_cloudfront_distribution.frontend_resources.arn
}
