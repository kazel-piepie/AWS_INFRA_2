# Internet-facing ALB for the socket server. Serves WebSocket traffic over HTTPS.
resource "aws_lb" "socket" {
  name               = "${local.name_prefix}-socket-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.socket_alb.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name      = "${local.name_prefix}-socket-alb"
    Component = "socket"
  }
}

# Target group for the socket EC2 instances (target_type instance for EC2).
resource "aws_lb_target_group" "socket" {
  name        = "${local.name_prefix}-socket-tg"
  port        = 5050
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

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
    Name      = "${local.name_prefix}-socket-tg"
    Component = "socket"
  }
}

resource "aws_lb_target_group_attachment" "socket_1" {
  target_group_arn = aws_lb_target_group.socket.arn
  target_id        = aws_instance.socket_1.id
  port             = 5050
}

resource "aws_lb_target_group_attachment" "socket_2" {
  target_group_arn = aws_lb_target_group.socket.arn
  target_id        = aws_instance.socket_2.id
  port             = 5050
}

# HTTPS listener (443) with ACM certificate, forwarding to the socket target group.
resource "aws_lb_listener" "socket_https" {
  load_balancer_arn = aws_lb.socket.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = data.aws_acm_certificate.rorr_club.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.socket.arn
  }

  tags = {
    Name = "${local.name_prefix}-socket-https"
  }
}
