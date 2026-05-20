# Generic Application Load Balancer.
# Supports public or internal mode, single HTTPS or HTTP listener, sticky sessions.

variable "name" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "internal" {
  type    = bool
  default = false
}
variable "ingress_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

# Listener
variable "listener_protocol" {
  type    = string
  default = "HTTPS"
} # HTTPS or HTTP
variable "listener_port" {
  type    = number
  default = 443
}
variable "certificate_arn" {
  type    = string
  default = null
}
variable "redirect_http_to_https" {
  type    = bool
  default = true
}

# Target group
variable "target_port" {
  type    = number
  default = 443
}
variable "target_protocol" {
  type    = string
  default = "HTTPS"
} # HTTPS or HTTP
variable "health_check_path" {
  type    = string
  default = "/"
}
variable "health_check_matcher" {
  type    = string
  default = "200-399"
}
variable "stickiness" {
  type    = bool
  default = true
}
variable "stickiness_duration" {
  type    = number
  default = 86400
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "ALB SG for ${var.name}"
  vpc_id      = var.vpc_id

  ingress {
    description = "Primary listener"
    from_port   = var.listener_port
    to_port     = var.listener_port
    protocol    = "tcp"
    cidr_blocks = var.ingress_cidrs
  }

  dynamic "ingress" {
    for_each = (var.listener_protocol == "HTTPS" && var.redirect_http_to_https) ? [80] : []
    content {
      description = "HTTP redirect"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = var.ingress_cidrs
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-alb-sg" })
}

resource "aws_lb" "this" {
  name               = "${var.name}-alb"
  load_balancer_type = "application"
  internal           = var.internal
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.subnet_ids
  idle_timeout       = 120

  tags = merge(var.tags, { Name = "${var.name}-alb" })
}

resource "aws_lb_target_group" "this" {
  name_prefix = substr(replace(var.name, "-", ""), 0, 6)
  port        = var.target_port
  protocol    = var.target_protocol
  vpc_id      = var.vpc_id

  health_check {
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = var.target_protocol
    matcher             = var.health_check_matcher
    healthy_threshold   = 2
    unhealthy_threshold = 5
    interval            = 30
    timeout             = 10
  }

  stickiness {
    type            = "lb_cookie"
    cookie_duration = var.stickiness_duration
    enabled         = var.stickiness
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, { Name = "${var.name}-tg" })
}

resource "aws_lb_listener" "primary" {
  load_balancer_arn = aws_lb.this.arn
  port              = var.listener_port
  protocol          = var.listener_protocol
  ssl_policy        = var.listener_protocol == "HTTPS" ? "ELBSecurityPolicy-TLS13-1-2-2021-06" : null
  certificate_arn   = var.listener_protocol == "HTTPS" ? var.certificate_arn : null

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

resource "aws_lb_listener" "http_redirect" {
  count             = (var.listener_protocol == "HTTPS" && var.redirect_http_to_https) ? 1 : 0
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = tostring(var.listener_port)
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

output "arn" { value = aws_lb.this.arn }
output "dns_name" { value = aws_lb.this.dns_name }
output "zone_id" { value = aws_lb.this.zone_id }
output "security_group_id" { value = aws_security_group.alb.id }
output "target_group_arn" { value = aws_lb_target_group.this.arn }
