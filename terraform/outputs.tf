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
  # The cluster is SASL/IAM-only (client_broker = TLS, sasl.iam = true), so the
  # plaintext bootstrap_brokers attribute is always empty. Consumers (kafka-ui,
  # backend) authenticate exclusively over SASL/IAM on port 9098, so expose the
  # sasl_iam endpoints here. This output feeds ai/rorr.msk_bootstrap_servers and
  # ai/rorr-infra.msk.bootstrap_brokers_iam via the terraform workflow.
  description = "MSK SASL/IAM bootstrap broker connection string (port 9098)"
  value       = aws_msk_cluster.main.bootstrap_brokers_sasl_iam
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

output "kafka_ui_instance_id" {
  description = "Kafka UI EC2 instance id"
  value       = aws_instance.kafka_ui.id
}

output "app_instance_ids" {
  description = "Application tier EC2 instance ids by component"
  value       = { for k, inst in aws_instance.app : k => inst.id }
}

output "rorr_secret_arn" {
  description = "ARN of the ai/rorr secret consumed by this stack"
  value       = data.aws_secretsmanager_secret.rorr.arn
}
output "main_db_instance_id" {
  description = "Main DB EC2 instance id"
  value       = aws_instance.main_db.id
}

output "socket_1_instance_id" {
  description = "Socket server node 1 EC2 instance id"
  value       = aws_instance.socket_1.id
}

output "socket_1_private_ip" {
  description = "Socket server node 1 private IP"
  value       = aws_instance.socket_1.private_ip
}

output "socket_2_instance_id" {
  description = "Socket server node 2 EC2 instance id"
  value       = aws_instance.socket_2.id
}

output "socket_2_private_ip" {
  description = "Socket server node 2 private IP"
  value       = aws_instance.socket_2.private_ip
}

output "main_db_private_dns" {
  description = "Main DB private DNS name"
  value       = aws_instance.main_db.private_dns
}

output "kafka_ui_private_dns" {
  description = "Kafka UI private DNS name"
  value       = aws_instance.kafka_ui.private_dns
}

output "socket_1_private_dns" {
  description = "Socket server node 1 private DNS name"
  value       = aws_instance.socket_1.private_dns
}

output "socket_2_private_dns" {
  description = "Socket server node 2 private DNS name"
  value       = aws_instance.socket_2.private_dns
}

output "main_db_availability_zone" {
  description = "Main DB availability zone"
  value       = aws_instance.main_db.availability_zone
}

output "kafka_ui_availability_zone" {
  description = "Kafka UI availability zone"
  value       = aws_instance.kafka_ui.availability_zone
}

output "socket_1_availability_zone" {
  description = "Socket server node 1 availability zone"
  value       = aws_instance.socket_1.availability_zone
}

output "socket_2_availability_zone" {
  description = "Socket server node 2 availability zone"
  value       = aws_instance.socket_2.availability_zone
}

output "socket_alb_dns_name" {
  description = "Socket ALB DNS name"
  value       = aws_lb.socket.dns_name
}

output "socket_alb_arn" {
  description = "Socket ALB ARN"
  value       = aws_lb.socket.arn
}

output "socket_alb_zone_id" {
  description = "Socket ALB hosted zone id (for Route 53 alias records)"
  value       = aws_lb.socket.zone_id
}

output "neo4j_private_ip" {
  description = "Neo4j private IP"
  value       = aws_instance.neo4j.private_ip
}

output "neo4j_instance_id" {
  description = "Neo4j EC2 instance id"
  value       = aws_instance.neo4j.id
}

output "neo4j_uri" {
  description = "Neo4j Bolt connection URI"
  value       = "bolt://${aws_instance.neo4j.private_ip}:7687"
}

output "neo4j_secret_arn" {
  description = "ARN of the dedicated rorr neo4j secret"
  value       = aws_secretsmanager_secret.neo4j.arn
}
