# ---------------------------------------------------------------------------
# RORR frontend infrastructure: S3 static origin, CloudFront distribution with
# Origin Access Control (OAC), and a dedicated least-privilege CI/CD IAM user
# whose credentials are stored in Secrets Manager.
# ---------------------------------------------------------------------------

# Pre-existing infra secret (created by MCP server prerequisite work). Only the
# frontend CI/CD user is granted read access to this exact ARN.
data "aws_secretsmanager_secret" "rorr_infra" {
  name = "ai/rorr-infra/${var.env}"
}

# AWS-managed CachingOptimized cache policy (default for static assets).
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

locals {
  frontend_bucket_name = "${local.name_prefix}-frontend"
  frontend_domain      = "ai-dev-app.rorr.club"
}

# ---------------------------------------------------------------------------
# S3 bucket for the frontend website (private; reached only via CloudFront OAC).
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "frontend" {
  bucket = local.frontend_bucket_name

  tags = {
    Name      = local.frontend_bucket_name
    Component = "frontend"
    Purpose   = "static-website-origin"
  }
}

# Block all public access; CloudFront OAC is the only allowed reader.
resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Bucket policy: allow only this CloudFront distribution (via OAC) to read.
data "aws_iam_policy_document" "frontend_bucket" {
  statement {
    sid    = "AllowCloudFrontOACRead"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.frontend.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.frontend.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = data.aws_iam_policy_document.frontend_bucket.json

  # Public access block must settle before attaching a bucket policy.
  depends_on = [aws_s3_bucket_public_access_block.frontend]
}

# ---------------------------------------------------------------------------
# CloudFront distribution fronting the private S3 bucket via OAC.
# ---------------------------------------------------------------------------
resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${local.name_prefix}-frontend-oac"
  description                       = "OAC for the RORR frontend S3 origin"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "RORR frontend distribution (${var.env})"
  default_root_object = "index.html"
  aliases             = [local.frontend_domain]
  price_class         = "PriceClass_100"

  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "s3-${local.frontend_bucket_name}"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-${local.frontend_bucket_name}"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
  }

  # SPA routing: serve index.html for client-side routes / missing keys.
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
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
    Name      = "${local.name_prefix}-frontend"
    Component = "frontend"
    Purpose   = "cdn"
  }
}

# ---------------------------------------------------------------------------
# Dedicated least-privilege IAM user for frontend CI/CD: read the infra secret,
# sync the S3 bucket, and invalidate the CloudFront cache.
# ---------------------------------------------------------------------------
resource "aws_iam_user" "frontend_cicd" {
  name = "${local.name_prefix}-frontend-cicd"
  path = "/cicd/"

  tags = {
    Name      = "${local.name_prefix}-frontend-cicd"
    Component = "frontend"
    Purpose   = "git-cicd-deploy"
  }
}

resource "aws_iam_access_key" "frontend_cicd" {
  user = aws_iam_user.frontend_cicd.name
}

data "aws_iam_policy_document" "frontend_cicd" {
  # Merge in the frontend-resources S3/CloudFront statements (defined in
  # frontend-resources.tf) so this user keeps a single inline policy,
  # ai-rorr-${env}-frontend-cicd-policy.
  source_policy_documents = [data.aws_iam_policy_document.frontend_cicd_resources.json]

  # --- Secrets Manager: only the ai/rorr-infra secret, read-only. ---
  statement {
    sid    = "ReadInfraSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [data.aws_secretsmanager_secret.rorr_infra.arn]
  }

  # --- S3: list the frontend bucket. ---
  statement {
    sid    = "ListFrontendBucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [aws_s3_bucket.frontend.arn]
  }

  # --- S3: read/write/delete objects in the frontend bucket. ---
  statement {
    sid    = "DeployFrontendObjects"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:GetObject",
    ]
    resources = ["${aws_s3_bucket.frontend.arn}/*"]
  }

  # --- CloudFront: invalidate the frontend distribution cache. ---
  statement {
    sid       = "InvalidateFrontendCache"
    effect    = "Allow"
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [aws_cloudfront_distribution.frontend.arn]
  }
}

resource "aws_iam_user_policy" "frontend_cicd" {
  name   = "${local.name_prefix}-frontend-cicd-policy"
  user   = aws_iam_user.frontend_cicd.name
  policy = data.aws_iam_policy_document.frontend_cicd.json
}

# ---------------------------------------------------------------------------
# Store the frontend CI/CD access key in its own Secrets Manager secret.
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "frontend_cicd_key" {
  name        = "ai/rorr-infra/${var.env}-frontend-cicd-key"
  description = "Access key for the RORR frontend CI/CD IAM user"

  tags = {
    Name      = "ai/rorr-infra/${var.env}-frontend-cicd-key"
    Component = "frontend"
    Purpose   = "cicd-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "frontend_cicd_key" {
  secret_id = aws_secretsmanager_secret.frontend_cicd_key.id
  secret_string = jsonencode({
    aws_access_key_id     = aws_iam_access_key.frontend_cicd.id
    aws_secret_access_key = aws_iam_access_key.frontend_cicd.secret
    user_name             = aws_iam_user.frontend_cicd.name
  })
}

# ---------------------------------------------------------------------------
# Outputs.
# ---------------------------------------------------------------------------
output "frontend_bucket_name" {
  description = "Frontend S3 bucket name"
  value       = aws_s3_bucket.frontend.bucket
}

output "frontend_cloudfront_domain_name" {
  description = "CloudFront distribution domain name (point ai-dev-app.rorr.club at this)"
  value       = aws_cloudfront_distribution.frontend.domain_name
}

output "frontend_cloudfront_distribution_id" {
  description = "CloudFront distribution id (for cache invalidations)"
  value       = aws_cloudfront_distribution.frontend.id
}

output "frontend_cicd_key_secret_arn" {
  description = "ARN of the secret holding the frontend CI/CD access key"
  value       = aws_secretsmanager_secret.frontend_cicd_key.arn
}
