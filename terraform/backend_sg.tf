# Security groups for the backend service.
# DB ingress from the backend task SG is added inline on aws_security_group.db
# (see security_groups.tf) to avoid mixing inline rules with rule resources.

# Internet-facing ALB security group: HTTPS only.
resource "aws_security_group" "backend_alb" {
  name        = "${local.backend_name}-alb-sg"
  description = "RORR backend ALB ingress HTTPS only"
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
    Name = "${local.backend_name}-alb-sg"
  }
}

# Backend Fargate task security group: only the ALB may reach the container port.
resource "aws_security_group" "backend_task" {
  name        = "${local.backend_name}-task-sg"
  description = "RORR backend Fargate tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Container port from backend ALB"
    from_port       = var.backend_container_port
    to_port         = var.backend_container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.backend_alb.id]
  }

  egress {
    description = "All outbound (ECR pull, Secrets Manager, DB via NAT)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.backend_name}-task-sg"
  }
}
