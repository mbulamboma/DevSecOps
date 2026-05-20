# =============================================================================
# Foreman stack
#   - Public ALB (HTTPS via ACM) at foreman.emlinkapp.com
#   - ASG (min 1 / max 2 / desired 1) running Foreman 3.12
#   - Connects to the RDS PostgreSQL provisioned by the puppetdb stack
# =============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.60" }
  }
  backend "local" {
    path = "../state/foreman.tfstate"
  }
}

provider "aws" {
  region = "us-east-2"
}

variable "rds_password" {
  type      = string
  sensitive = true
}
variable "foreman_admin_password" {
  type        = string
  sensitive   = true
  description = "Admin password for Foreman. Set via TF_VAR_foreman_admin_password or -var flag."
  # IMPORTANT: Do not set a default value here. Pass securely via environment variable or tfvars.
}

locals {
  project  = "foreman"
  app_port = 443
  fqdn     = "foreman.emlinkapp.com"

  vpc_id              = "vpc-0aedda8091caa685a"
  key_name            = "k8s-key"
  ami_id              = "ami-024e6efaf93d85776"
  hosted_zone_id      = "Z03818813PJNSZYB1JRT6"
  acm_certificate_arn = "arn:aws:acm:us-east-2:034911605638:certificate/f92dd53e-39ec-49e1-a08d-0218b044b1f7"

  rds_username = "puppetadmin"

  tags = {
    Project   = local.project
    ManagedBy = "Terraform"
  }
}

module "network" {
  source = "../modules/network-data"
  vpc_id = local.vpc_id
}

# Read the puppetdb stack's RDS + SG IDs from its state file
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
  subnet_ids        = module.network.public_subnet_ids
  internal          = false
  listener_protocol = "HTTPS"
  listener_port     = 443
  certificate_arn   = local.acm_certificate_arn
  target_protocol   = "HTTPS"
  target_port       = 443
  health_check_path = "/users/login"
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
  app_port              = 443
  min_size              = 1
  max_size              = 2
  desired_capacity      = 1

  user_data = templatefile("${path.module}/user-data/foreman.sh.tftpl", {
    rds_host       = split(":", data.terraform_remote_state.puppetdb.outputs.rds_endpoint)[0]
    rds_port       = 5432
    rds_user       = local.rds_username
    rds_password   = var.rds_password
    fqdn           = local.fqdn
    admin_password = var.foreman_admin_password
  })

  tags = local.tags
}

# Allow Foreman EC2 to reach the puppetdb RDS
resource "aws_security_group_rule" "foreman_to_rds" {
  type                     = "ingress"
  security_group_id        = data.terraform_remote_state.puppetdb.outputs.rds_security_group_id
  protocol                 = "tcp"
  from_port                = 5432
  to_port                  = 5432
  source_security_group_id = module.asg.security_group_id
  description              = "Foreman to shared RDS"
}

module "dns" {
  source                = "../modules/route53-alias"
  hosted_zone_id        = local.hosted_zone_id
  name                  = local.fqdn
  alias_target_dns_name = module.alb.dns_name
  alias_target_zone_id  = module.alb.zone_id
}

output "alb_dns_name" { value = module.alb.dns_name }
output "fqdn" { value = local.fqdn }
output "ec2_security_group_id" { value = module.asg.security_group_id }
