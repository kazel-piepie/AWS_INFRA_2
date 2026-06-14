# Application tier: collectors, live events processors, LoL AI.
resource "aws_security_group" "app" {
  name        = "${local.name_prefix}-app-sg"
  description = "RORR application tier (collectors, live events, AI)"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-app-sg"
  }
}

# Main DB (PostgreSQL + TimescaleDB).
resource "aws_security_group" "db" {
  name        = "${local.name_prefix}-db-sg"
  description = "RORR main database PostgreSQL TimescaleDB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from application tier"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  # Backend ECS Fargate tasks connect to the main DB (PostgreSQL 5432).
  ingress {
    description     = "PostgreSQL from backend ECS tasks"
    from_port       = var.backend_db_port
    to_port         = var.backend_db_port
    protocol        = "tcp"
    security_groups = [aws_security_group.backend_ecs.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-db-sg"
  }
}

# ElastiCache Redis.
resource "aws_security_group" "redis" {
  name        = "${local.name_prefix}-redis-sg"
  description = "RORR Redis ElastiCache"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Redis from application tier"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  # LOL backend deliverers/collector cache to Redis via the backend ECS SG.
  ingress {
    description     = "Redis from backend ECS tasks"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.backend_ecs.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-redis-sg"
  }
}

# Kafka UI monitoring host.
resource "aws_security_group" "kafka_ui" {
  name        = "${local.name_prefix}-kafka-ui-sg"
  description = "RORR Kafka UI monitoring host"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Kafka UI web from within VPC"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-kafka-ui-sg"
  }
}

# MSK (Kafka) brokers.
resource "aws_security_group" "msk" {
  name        = "${local.name_prefix}-msk-sg"
  description = "RORR MSK Kafka brokers"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Kafka plaintext from application tier"
    from_port       = 9092
    to_port         = 9092
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  ingress {
    description     = "Kafka TLS from application tier"
    from_port       = 9094
    to_port         = 9094
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  ingress {
    description     = "Kafka plaintext from Kafka UI"
    from_port       = 9092
    to_port         = 9092
    protocol        = "tcp"
    security_groups = [aws_security_group.kafka_ui.id]
  }

  # LOL backend pipeline ECS tasks reach MSK via the shared backend ECS SG.
  ingress {
    description     = "Kafka plaintext from backend ECS tasks"
    from_port       = 9092
    to_port         = 9092
    protocol        = "tcp"
    security_groups = [aws_security_group.backend_ecs.id]
  }

  ingress {
    description     = "Kafka TLS from backend ECS tasks"
    from_port       = 9094
    to_port         = 9094
    protocol        = "tcp"
    security_groups = [aws_security_group.backend_ecs.id]
  }

  ingress {
    description     = "Kafka IAM auth from backend ECS tasks"
    from_port       = 9098
    to_port         = 9098
    protocol        = "tcp"
    security_groups = [aws_security_group.backend_ecs.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-msk-sg"
  }
}
