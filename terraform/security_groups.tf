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

  # ai-service ECS Fargate tasks connect to the main DB (PostgreSQL 5432).
  ingress {
    description     = "PostgreSQL from ai-service ECS tasks"
    from_port       = var.backend_db_port
    to_port         = var.backend_db_port
    protocol        = "tcp"
    security_groups = [aws_security_group.ai_ecs.id]
  }

  # object-simulator ECS Fargate task reads game_combat_event / live_game (5432).
  ingress {
    description     = "PostgreSQL from object-simulator ECS task"
    from_port       = var.backend_db_port
    to_port         = var.backend_db_port
    protocol        = "tcp"
    security_groups = [aws_security_group.sim_ecs.id]
  }

  ingress {
    description     = "PostgreSQL from socket EC2 instances"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.socket_ec2.id]
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

# Neo4j graph database.
resource "aws_security_group" "neo4j" {
  name        = "${local.name_prefix}-neo4j-sg"
  description = "RORR Neo4j graph database"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Bolt from application tier"
    from_port       = 7687
    to_port         = 7687
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  ingress {
    description     = "Bolt from backend ECS tasks"
    from_port       = 7687
    to_port         = 7687
    protocol        = "tcp"
    security_groups = [aws_security_group.backend_ecs.id]
  }

  ingress {
    description     = "Bolt from socket EC2 instances"
    from_port       = 7687
    to_port         = 7687
    protocol        = "tcp"
    security_groups = [aws_security_group.socket_ec2.id]
  }

  ingress {
    description = "Neo4j HTTP browser from within VPC"
    from_port   = 7474
    to_port     = 7474
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
    Name = "${local.name_prefix}-neo4j-sg"
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

  # ai-service ECS Fargate tasks cache to Redis (6379).
  ingress {
    description     = "Redis from ai-service ECS tasks"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ai_ecs.id]
  }

  # object-simulator ECS Fargate task caches to Redis (6379).
  ingress {
    description     = "Redis from object-simulator ECS task"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.sim_ecs.id]
  }

  # Allow Redis access from kafka-ui EC2 used as SSM port-forwarding jump host for dev access.
  ingress {
    description     = "Redis from kafka-ui EC2 for SSM port forwarding"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.kafka_ui.id]
  }

  ingress {
    description     = "Redis from socket EC2 instances"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.socket_ec2.id]
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

# Ollama model-serving host. Inbound only from the ai-service ECS tasks on the
# Ollama API port (11434); all outbound.
resource "aws_security_group" "ollama" {
  name        = "${local.name_prefix}-ollama-sg"
  description = "RORR Ollama model serving host"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Ollama API from ai-service ECS tasks"
    from_port       = 11434
    to_port         = 11434
    protocol        = "tcp"
    security_groups = [aws_security_group.ai_ecs.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-ollama-sg"
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

  # object-simulator produces object-events over SASL/IAM (9098). The cluster is
  # IAM-only, so 9092/9094 are unreachable and intentionally not opened here.
  ingress {
    description     = "Kafka IAM auth from object-simulator ECS task"
    from_port       = 9098
    to_port         = 9098
    protocol        = "tcp"
    security_groups = [aws_security_group.sim_ecs.id]
  }

  ingress {
    description     = "Kafka IAM auth from Kafka UI"
    from_port       = 9098
    to_port         = 9098
    protocol        = "tcp"
    security_groups = [aws_security_group.kafka_ui.id]
  }

  # ai-service consumes object-events over SASL/IAM (9098). IAM-only cluster, so
  # 9092/9094 stay closed for this source.
  ingress {
    description     = "Kafka IAM auth from ai-service ECS tasks"
    from_port       = 9098
    to_port         = 9098
    protocol        = "tcp"
    security_groups = [aws_security_group.ai_ecs.id]
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

# Socket server internet-facing ALB. HTTPS (443) inbound; all outbound.
resource "aws_security_group" "socket_alb" {
  name        = "${local.name_prefix}-socket-alb-sg"
  description = "RORR socket server ALB internet facing HTTPS only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-socket-alb-sg"
  }
}

# Socket server EC2 instances. Inbound only from the socket ALB on port 5050.
resource "aws_security_group" "socket_ec2" {
  name        = "${local.name_prefix}-socket-ec2-sg"
  description = "RORR socket server EC2 instances"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Socket traffic from socket ALB"
    from_port       = 5050
    to_port         = 5050
    protocol        = "tcp"
    security_groups = [aws_security_group.socket_alb.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-socket-ec2-sg"
  }
}

# object-simulator internet-facing ALB. HTTPS (443) inbound; all outbound.
# NOTE: ingress is 0.0.0.0/0 as a placeholder. The operator MUST narrow this to
# the real allow-list CIDRs before relying on it in the open internet - the
# actual allow-list IPs are unknown at authoring time so they are not guessed.
resource "aws_security_group" "sim_alb" {
  name        = "${local.name_prefix}-sim-alb-sg"
  description = "RORR object-simulator ALB internet facing HTTPS only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from anywhere (placeholder - narrow to allow-list CIDRs)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-sim-alb-sg"
  }
}

# object-simulator ECS Fargate task. Inbound only from the simulator ALB on the
# container port (3000); all outbound (reaches MSK / DB / Redis via NAT).
resource "aws_security_group" "sim_ecs" {
  name        = "${local.name_prefix}-sim-ecs-sg"
  description = "RORR object-simulator ECS Fargate task"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "App traffic from object-simulator ALB"
    from_port       = var.simulator_container_port
    to_port         = var.simulator_container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.sim_alb.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-sim-ecs-sg"
  }
}
