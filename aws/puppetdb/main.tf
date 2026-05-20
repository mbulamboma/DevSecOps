# =============================================================================
# PuppetDB stack
#   - Internal ALB (private subnets) on HTTP:8080
#   - ASG (min 1 / max 2 / desired 1) running PuppetDB
#   - Dedicated RDS PostgreSQL backing the PuppetDB data store
# All inputs are inlined here per the project's "max 3 files at stack root" rule.
# Sensitive values are read from TF_VAR_rds_password.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.60" }
  }
  backend "local" {
    path = "../state/puppetdb.tfstate"
  }
}

provider "aws" {
  region = "us-east-2"
}

variable "rds_password" {
  type      = string
  sensitive = true
}

locals {
  project  = "puppetdb"
  app_port = 8080

  vpc_id   = "vpc-0aedda8091caa685a"
  key_name = "k8s-key"
  ami_id   = "ami-024e6efaf93d85776"

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

module "rds" {
  source                     = "../modules/rds-postgres"
  identifier                 = "${local.project}-pg"
  vpc_id                     = local.vpc_id
  subnet_ids                 = module.network.private_subnet_ids
  allowed_security_group_ids = [module.asg.security_group_id]
  database_name              = "puppetdb"
  username                   = local.rds_username
  password                   = var.rds_password
  tags                       = local.tags
}

module "alb" {
  source            = "../modules/alb"
  name              = local.project
  vpc_id            = local.vpc_id
  subnet_ids        = module.network.private_subnet_ids
  internal          = true
  ingress_cidrs     = ["10.0.0.0/16"]
  listener_protocol = "HTTP"
  listener_port     = local.app_port
  target_protocol   = "HTTP"
  target_port       = local.app_port
  health_check_path = "/pdb/meta/v1/version"
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

  user_data = templatefile("${path.module}/user-data/puppetdb.sh.tftpl", {
    rds_host     = module.rds.endpoint_host
    rds_port     = module.rds.port
    rds_user     = local.rds_username
    rds_password = var.rds_password
  })

  tags = local.tags
}

output "alb_dns_name" { value = module.alb.dns_name }
output "alb_security_group_id" { value = module.alb.security_group_id }
output "ec2_security_group_id" { value = module.asg.security_group_id }
output "rds_endpoint" { value = module.rds.endpoint }
output "rds_security_group_id" { value = module.rds.security_group_id }
