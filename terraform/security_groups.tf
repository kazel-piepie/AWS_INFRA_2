# Main DB (PostgreSQL + TimescaleDB).
resource "aws_security_group" "db" {
  name        = "${local.name_prefix}-db-sg"
  description = "RORR main database PostgreSQL TimescaleDB"
  vpc_id      = aws_vpc.main.id

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
    description     = "Kafka plaintext from Kafka UI"
    from_port       = 9092
    to_port         = 9092
    protocol        = "tcp"
    security_groups = [aws_security_group.kafka_ui.id]
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
