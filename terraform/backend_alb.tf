# Dedicated internet-facing ALB for the backend service (HTTPS only).
resource "aws_lb" "backend" {
  name               = "${local.backend_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.backend_alb.id]
  subnets            = aws_subnet.public[*].id

  # Session timeout: hold idle connections for the configured window.
  idle_timeout = var.backend_session_timeout_seconds

  tags = {
    Name = "${local.backend_name}-alb"
  }
}

resource "aws_lb_target_group" "backend" {
  name        = "${local.backend_name}-tg"
  port        = var.backend_container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = var.backend_health_check_path
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  # Sticky sessions for the configured session timeout window.
  stickiness {
    type            = "lb_cookie"
    cookie_duration = var.backend_session_timeout_seconds
    enabled         = true
  }

  tags = {
    Name = "${local.backend_name}-tg"
  }
}

# HTTPS-only listener. No plain HTTP listener is created.
resource "aws_lb_listener" "backend_https" {
  load_balancer_arn = aws_lb.backend.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = data.aws_acm_certificate.rorr.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
}
