resource "aws_elasticache_subnet_group" "redis" {
  name        = "${local.name_prefix}-redis-subnets"
  description = "RORR Redis subnet group"
  subnet_ids  = aws_subnet.private[*].id
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "${local.name_prefix}-redis"
  engine               = "redis"
  node_type            = local.redis_node_type[var.env]
  num_cache_nodes      = local.redis_num_nodes[var.env]
  port                 = 6379
  parameter_group_name = "default.redis7"
  subnet_group_name    = aws_elasticache_subnet_group.redis.name
  security_group_ids   = [aws_security_group.redis.id]

  tags = {
    Name = "${local.name_prefix}-redis"
  }
}
