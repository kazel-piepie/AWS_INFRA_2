# ai-service outputs. ai_service_ecs is consumed by CI/CD to merge an
# ecs.ai_service descriptor into ai/rorr-infra/{env} (see terraform.yml).

output "ai_service_ecr_repository_url" {
  description = "ECR repository URL for the ai-service image"
  value       = aws_ecr_repository.ai.repository_url
}

output "ai_service_ecs_cluster_name" {
  description = "ECS cluster hosting the ai-service (existing backend cluster)"
  value       = aws_ecs_cluster.backend.name
}

output "ai_service_ecs_service_name" {
  description = "ai-service ECS service name"
  value       = aws_ecs_service.ai.name
}

output "ai_service_connect_dns" {
  description = "In-cluster Service Connect DNS name backend-service uses to reach the ai-service"
  value       = "ai-service"
}

# Same field structure as the existing ecs.backend object in ai/rorr-infra/{env}.
output "ai_service_ecs" {
  description = "ai-service ECS descriptor merged into ai/rorr-infra ecs.ai_service"
  value = {
    cluster_name    = aws_ecs_cluster.backend.name
    service_name    = aws_ecs_service.ai.name
    task_definition = aws_ecs_task_definition.ai.arn
    ecr_repository  = aws_ecr_repository.ai.name
    container_name  = "ai"
    container_port  = var.ai_container_port
  }
}
