# LOL backend pipeline outputs.

output "lol_backend_ecr_repository_url" {
  description = "ECR repository URL for the shared rorr-lol-backend image"
  value       = aws_ecr_repository.lol_backend.repository_url
}

output "lol_backend_service_names" {
  description = "ECS service names for the LOL backend pipeline modules"
  value       = sort([for s in aws_ecs_service.lol : s.name])
}

output "lol_backend_deploy_role_arn" {
  description = "GitHub OIDC deploy role ARN for the LOL backend pipeline"
  value       = aws_iam_role.lol_deploy.arn
}

output "github_oidc_provider_arn" {
  description = "GitHub Actions OIDC provider ARN"
  value       = aws_iam_openid_connect_provider.github.arn
}

# --- object-relay / object-simulator (feeds the rorr secret-merge steps) ----

output "lol_object_relay_service_arn" {
  description = "ECS service ARN for rorr-lol-object-relay"
  value       = aws_ecs_service.lol["rorr-lol-object-relay"].id
}

output "lol_object_simulator_service_arn" {
  description = "ECS service ARN for rorr-lol-object-simulator"
  value       = aws_ecs_service.object_simulator.id
}

output "lol_object_event_topics" {
  description = "MSK topic names produced by object-relay / object-simulator"
  value = {
    object_events     = "rorr-lol-object-events"
    object_events_dlq = "rorr-lol-object-events-dlq"
  }
}

output "simulator_alb_dns_name" {
  description = "object-simulator ALB DNS name (target for an external CNAME, e.g. ai-dev-sim.rorr.club)"
  value       = aws_lb.simulator.dns_name
}

output "simulator_alb_arn" {
  description = "object-simulator ALB ARN"
  value       = aws_lb.simulator.arn
}

output "simulator_alb_zone_id" {
  description = "object-simulator ALB hosted zone id (for Route 53 alias records)"
  value       = aws_lb.simulator.zone_id
}
