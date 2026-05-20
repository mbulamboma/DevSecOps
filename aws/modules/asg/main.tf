# Auto Scaling Group fronted by a target group.
# Creates: SG (allowing app traffic from alb_security_group_id), Launch Template, ASG.

variable "name" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "ami_id" { type = string }
variable "instance_type" { type = string }
variable "key_name" { type = string }
variable "user_data" { type = string }
variable "target_group_arn" { type = string }

variable "app_port" { type = number }
variable "alb_security_group_id" { type = string }

variable "min_size" {
  type    = number
  default = 1
}
variable "max_size" {
  type    = number
  default = 2
}
variable "desired_capacity" {
  type    = number
  default = 1
}

variable "assign_public_ip" {
  type    = bool
  default = false
}
variable "volume_size" {
  type    = number
  default = 30
}
variable "ssh_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}
variable "extra_ingress" {
  description = "Additional ingress rules: list of { from_port, to_port, protocol, source_security_group_id, description }"
  type = list(object({
    from_port                = number
    to_port                  = number
    protocol                 = string
    source_security_group_id = string
    description              = string
  }))
  default = []
}

variable "health_check_grace_period" {
  type    = number
  default = 1500
}

variable "health_check_type" {
  description = "ELB (default) or EC2. Use EC2 for stacks where the ALB target group is cosmetic (e.g. puppet-master mTLS that ALB can't proxy)."
  type        = string
  default     = "ELB"
}

variable "iam_instance_profile" {
  description = "Optional IAM instance profile name to attach to the launch template."
  type        = string
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "aws_security_group" "ec2" {
  name        = "${var.name}-ec2"
  description = "EC2 SG for ${var.name}"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_cidrs
  }

  ingress {
    description     = "App from ALB"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
  }

  dynamic "ingress" {
    for_each = var.extra_ingress
    content {
      description     = ingress.value.description
      from_port       = ingress.value.from_port
      to_port         = ingress.value.to_port
      protocol        = ingress.value.protocol
      security_groups = [ingress.value.source_security_group_id]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-ec2-sg" })
}

resource "aws_launch_template" "this" {
  name_prefix   = "${var.name}-lt-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name
  # SGs go on the network interface (cannot use both vpc_security_group_ids and
  # network_interfaces.security_groups - AWS rejects the combination).

  user_data = base64encode(var.user_data)

  dynamic "iam_instance_profile" {
    for_each = var.iam_instance_profile == null ? [] : [var.iam_instance_profile]
    content {
      name = iam_instance_profile.value
    }
  }

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  network_interfaces {
    associate_public_ip_address = var.assign_public_ip
    security_groups             = [aws_security_group.ec2.id]
  }

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size           = var.volume_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = var.name })
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "this" {
  name_prefix         = "${var.name}-asg-"
  min_size            = var.min_size
  max_size            = var.max_size
  desired_capacity    = var.desired_capacity
  vpc_zone_identifier = var.subnet_ids
  target_group_arns   = [var.target_group_arn]
  health_check_type   = var.health_check_type
  health_check_grace_period = var.health_check_grace_period

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 0
    }
  }

  dynamic "tag" {
    for_each = merge(var.tags, { Name = var.name })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

output "security_group_id" { value = aws_security_group.ec2.id }
output "asg_name" { value = aws_autoscaling_group.this.name }
