# ECR repository for the MCP datacenter Fargate service.
resource "aws_ecr_repository" "datacenter" {
  name                 = "ai-mcp-dev-datacenter"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name      = "ai-mcp-dev-datacenter"
    Component = "datacenter"
  }
}

resource "aws_ecr_lifecycle_policy" "datacenter" {
  repository = aws_ecr_repository.datacenter.name

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
