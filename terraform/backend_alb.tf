# Security group for the internet-facing backend ALB.
# HTTPS (443) only — no plain HTTP listener is served.
resource "aws_security_group" "backend_alb" {
  name        = "${local.name_prefix}-backend-alb-sg"
  description = "RORR backend ALB internet facing HTTPS and datacenter port"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Datacenter service HTTP"
    from_port   = 444
    to_port     = 444
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

# Target group for the backend Fargate tasks (target_type ip for awsvpc).
# Stickiness with a 600s cookie so sessions time out at 10 minutes.
resource "aws_lb_target_group" "backend" {
  name        = "${local.name_prefix}-backend-tg"
  port        = var.backend_container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  stickiness {
    type            = "lb_cookie"
    enabled         = true
    cookie_duration = var.backend_session_timeout
  }

  health_check {
    enabled             = true
    path                = var.backend_health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = {
    Name      = "${local.name_prefix}-backend-tg"
    Component = "backend"
  }
}

# HTTPS listener (443) only, using the rorr.club ACM certificate and a strong
# TLS 1.3 policy. No port 80 listener is created (HTTPS only).
resource "aws_lb_listener" "backend_https" {
  load_balancer_arn = aws_lb.backend.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = data.aws_acm_certificate.rorr_club.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  tags = {
    Name = "${local.name_prefix}-backend-https"
  }
}

# Target group for the MCP datacenter Fargate service (port 444).
resource "aws_lb_target_group" "datacenter" {
  name        = "${local.name_prefix}-datacenter-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = {
    Name      = "${local.name_prefix}-datacenter-tg"
    Component = "datacenter"
  }
}

# HTTP listener on port 444 for the MCP datacenter service.
resource "aws_lb_listener" "datacenter_444" {
  load_balancer_arn = aws_lb.backend.arn
  port              = 444
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.datacenter.arn
  }

  tags = {
    Name = "${local.name_prefix}-datacenter-444"
  }
}
