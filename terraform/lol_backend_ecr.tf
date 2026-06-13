# ---------------------------------------------------------------------------
# LOL backend pipeline: single ECR repository shared by all 8 modules.
# CI/CD builds one image and pushes a tag per deploy; each ECS service pulls it.
# Exact repository name per task spec (no ai- prefix): rorr-lol-backend.
# ---------------------------------------------------------------------------
resource "aws_ecr_repository" "lol_backend" {
  name                 = "rorr-lol-backend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name      = "rorr-lol-backend"
    Component = "lol-backend"
  }
}

# Keep only the most recent images to control storage cost.
resource "aws_ecr_lifecycle_policy" "lol_backend" {
  repository = aws_ecr_repository.lol_backend.name

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
