# ECR repository for the ai-service (LoL AI companion) Docker image.
# CI/CD (Git) builds and pushes images here, then updates the ECS service.
resource "aws_ecr_repository" "ai" {
  name                 = "${local.name_prefix}-ai"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name      = "${local.name_prefix}-ai"
    Component = "ai-service"
  }
}

# Keep only the most recent images to control storage cost on develop.
resource "aws_ecr_lifecycle_policy" "ai" {
  repository = aws_ecr_repository.ai.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
