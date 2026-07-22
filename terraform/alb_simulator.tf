# ---------------------------------------------------------------------------
# Internet-facing ALB dedicated to the rorr-lol-object-simulator ECS service.
# Reuses the existing public subnets and the existing *.rorr.club wildcard ACM
# certificate (data.aws_acm_certificate.rorr_club) - no new certificate is
# requested here. The simulator task SG (aws_security_group.sim_ecs) only
# accepts traffic from this ALB's SG on the container port.
#
# DNS is out of scope: after apply, an external DNS record (e.g. a CNAME for
# ai-dev-sim.rorr.club) must point at this ALB's DNS name.
# ---------------------------------------------------------------------------
resource "aws_lb" "simulator" {
  name               = "${local.name_prefix}-sim-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.sim_alb.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name      = "${local.name_prefix}-sim-alb"
    Component = "lol-backend"
  }
}

# Target group for the simulator Fargate task (target_type ip for awsvpc).
resource "aws_lb_target_group" "simulator" {
  name        = "${local.name_prefix}-sim-tg"
  port        = var.simulator_container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = var.simulator_health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = {
    Name      = "${local.name_prefix}-sim-tg"
    Component = "lol-backend"
  }
}

# HTTPS listener (443) only, using the existing *.rorr.club ACM certificate and
# a strong TLS 1.3 policy. No port 80 listener is created (HTTPS only).
resource "aws_lb_listener" "simulator_https" {
  load_balancer_arn = aws_lb.simulator.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = data.aws_acm_certificate.rorr_club.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.simulator.arn
  }

  tags = {
    Name = "${local.name_prefix}-sim-https"
  }
}
