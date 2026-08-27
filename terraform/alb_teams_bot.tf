# Internet-facing ALB for the Teams Bot ECS service. HTTPS (443) only, using the
# existing *.rorr.club ACM certificate (data.aws_acm_certificate.rorr_club,
# declared in data.tf — referenced here, never re-declared).

resource "aws_lb" "teams_bot" {
  name               = "${local.name_prefix}-teams-bot-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.teams_bot_alb.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name      = "${local.name_prefix}-teams-bot-alb"
    Component = "teams-bot"
  }
}

resource "aws_lb_target_group" "teams_bot" {
  name        = "${local.name_prefix}-teams-bot-tg"
  port        = 3978
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/health"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name      = "${local.name_prefix}-teams-bot-tg"
    Component = "teams-bot"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "teams_bot_https" {
  load_balancer_arn = aws_lb.teams_bot.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = data.aws_acm_certificate.rorr_club.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.teams_bot.arn
  }

  tags = {
    Name      = "${local.name_prefix}-teams-bot-https"
    Component = "teams-bot"
  }
}
