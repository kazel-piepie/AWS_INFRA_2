output "vpc_id" {
  description = "RORR VPC id"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "Private subnet ids"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "Public subnet ids"
  value       = aws_subnet.public[*].id
}

output "msk_bootstrap_brokers" {
  description = "MSK plaintext bootstrap broker connection string"
  value       = aws_msk_cluster.main.bootstrap_brokers
}

output "msk_bootstrap_brokers_tls" {
  description = "MSK TLS bootstrap broker connection string"
  value       = aws_msk_cluster.main.bootstrap_brokers_tls
}

output "redis_endpoint" {
  description = "Redis primary endpoint address"
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
}

output "redis_port" {
  description = "Redis port"
  value       = aws_elasticache_cluster.redis.port
}

output "main_db_private_ip" {
  description = "Main DB private IP"
  value       = aws_instance.main_db.private_ip
}

output "kafka_ui_private_ip" {
  description = "Kafka UI private IP"
  value       = aws_instance.kafka_ui.private_ip
}

output "app_instance_ids" {
  description = "Application tier EC2 instance ids by component"
  value       = { for k, inst in aws_instance.app : k => inst.id }
}

output "main_db_instance_id" {
  description = "Main DB EC2 instance id"
  value       = aws_instance.main_db.id
}

output "rorr_secret_arn" {
  description = "ARN of the ai/rorr secret consumed by this stack"
  value       = data.aws_secretsmanager_secret.rorr.arn
}
