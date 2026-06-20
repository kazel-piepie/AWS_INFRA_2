# Security group for the internet-facing backend ALB.
# HTTPS (443) only — no plain HTTP listener is served.
resource "aws_security_group" "backend_alb" {
  name        = "${local.name_prefix}-backend-alb-sg"
  description = "RORR backend ALB internet facing HTTPS only"
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
    Name = "${local.name_prefix}-backend-alb-sg"
  }
}

# Internet-facing ALB for the backend service. Idle timeout set to the session
# timeout (600s / 10 minutes).
resource "aws_lb" "backend" {
  name               = "${local.name_prefix}-backend-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.backend_alb.id]
  subnets            = aws_subnet.public[*].id

  idle_timeout = var.backend_session_timeout

  tags = {
    Name      = "${local.name_prefix}-backend-alb"
    Component = "backend"
  }
}
