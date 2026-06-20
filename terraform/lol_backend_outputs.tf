# LOL backend pipeline outputs.

output "lol_backend_ecr_repository_url" {
  description = "ECR repository URL for the shared rorr-lol-backend image"
  value       = aws_ecr_repository.lol_backend.repository_url
}
