# =============================================================================
# Puppet Master stack
#   - Internal ALB (HTTP:8140) for Puppet agents inside the VPC
#   - ASG (min 1 / max 2 / desired 1) running puppetserver
#   - Talks to PuppetDB through the puppetdb stack's internal ALB
#   - GitOps: r10k pulls control_repo_url every minute -> serves catalogs
# =============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.60" }
  }
  backend "local" {
    path = "../state/puppet-masters.tfstate"
  }
}

provider "aws" {
  region = "us-east-2"
}

variable "control_repo_url" {
  description = "Git URL of the Puppet control repo (HTTPS or git@github.com:...). Leave empty to skip r10k."
  type        = string
  default     = "https://github.com/mbulamboma/devsecops-puppet-control.git"
}

variable "control_repo_deploy_key" {
  description = "Optional SSH private key (PEM contents) for a private control repo."
  type        = string
  sensitive   = true
  default     = ""
}

locals {
  project  = "puppet-master"
  app_port = 8140

  vpc_id   = "vpc-0aedda8091caa685a"
  key_name = "k8s-key"
  ami_id   = "ami-024e6efaf93d85776"

  tags = {
    Project   = local.project
    ManagedBy = "Terraform"
  }
}

module "network" {
  source = "../modules/network-data"
  vpc_id = local.vpc_id
}

data "terraform_remote_state" "puppetdb" {
  backend = "local"
  config = {
    path = "../state/puppetdb.tfstate"
  }
}

module "alb" {
  source            = "../modules/alb"
  name              = local.project
  vpc_id            = local.vpc_id
  subnet_ids        = module.network.private_subnet_ids
  internal          = true
  ingress_cidrs     = ["10.0.0.0/16"]
  # Puppetserver speaks HTTPS-mTLS on 8140 and cannot be load-balanced via a
  # layer-7 ALB (ALB would terminate TLS and the master would never see the
  # agent client cert). The ALB here exists only to provide a stable internal
  # DNS for tools / dashboards; agents talk DIRECTLY to the master via its
  # private IP published in SSM (/puppet/master/private-ip).
  # We disable the ALB-based ASG health check (see asg health_check_type below)
  # so this target-group being "unhealthy" never recycles the instance.
  listener_protocol = "HTTP"
  listener_port     = local.app_port
  target_protocol   = "HTTP"
  target_port       = local.app_port
  health_check_path = "/"
  health_check_matcher = "200-499"
  tags              = local.tags
}

module "asg" {
  source                = "../modules/asg"
  name                  = local.project
  vpc_id                = local.vpc_id
  subnet_ids            = module.network.public_subnet_ids
  ami_id                = local.ami_id
  instance_type         = "t3.medium"
  key_name              = local.key_name
  assign_public_ip      = true
  target_group_arn      = module.alb.target_group_arn
  alb_security_group_id = module.alb.security_group_id
  app_port              = local.app_port
  min_size              = 1
  max_size              = 2
  desired_capacity      = 1
  # ELB health check would terminate the instance because the layer-7 ALB can
  # never proxy puppetserver's HTTPS-mTLS on 8140. Use EC2 health check only.
  health_check_type    = "EC2"
  iam_instance_profile = aws_iam_instance_profile.puppet_master.name

  user_data = templatefile("${path.module}/user-data/puppet-master.sh.tftpl", {
    puppetdb_host           = data.terraform_remote_state.puppetdb.outputs.alb_dns_name
    puppetdb_port           = 8080
    control_repo_url        = var.control_repo_url
    control_repo_deploy_key = var.control_repo_deploy_key
  })

  tags = local.tags
}

# -----------------------------------------------------------------------------
# IAM role: master publishes its own private IP to SSM so k8s slaves can
# discover it (no ALB-mTLS proxy possible; agents must speak directly to master)
# -----------------------------------------------------------------------------
data "aws_caller_identity" "current" {}

resource "aws_iam_role" "puppet_master" {
  name = "puppet-master-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "puppet_master_ssm" {
  name = "puppet-master-ssm-publish"
  role = aws_iam_role.puppet_master.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:GetParameter",
          "ssm:DeleteParameter",
          "ssm:AddTagsToResource",
        ]
        Resource = "arn:aws:ssm:us-east-2:${data.aws_caller_identity.current.account_id}:parameter/puppet/*"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances", "ec2:DescribeTags"]
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_instance_profile" "puppet_master" {
  name = "puppet-master-profile"
  role = aws_iam_role.puppet_master.name
}

# Allow puppet-master EC2 to reach the PuppetDB internal ALB (:8080)
resource "aws_security_group_rule" "master_to_puppetdb_alb" {
  type                     = "ingress"
  security_group_id        = data.terraform_remote_state.puppetdb.outputs.alb_security_group_id
  protocol                 = "tcp"
  from_port                = 8080
  to_port                  = 8080
  source_security_group_id = module.asg.security_group_id
  description              = "puppet-master to puppetdb ALB"
}

output "alb_dns_name" { value = module.alb.dns_name }
output "ec2_security_group_id" { value = module.asg.security_group_id }
