# =============================================================================
# Kubernetes Worker node (single EC2, PRIVATE subnet)
#
# - Private subnet, no public IP, SSH only via the EICE created by the
#   control-plane stack.
# - IAM role lets the worker READ the kubeadm join command from SSM Parameter
#   Store (written there by the control-plane via Puppet).
# - user-data installs puppet-agent only; Puppet installs kubeadm and runs
#   the join with the SSM-fetched command.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.60" }
  }
  backend "local" {
    path = "../../state/k8s-worker-node.tfstate"
  }
}

provider "aws" {
  region = "us-east-2"
}

locals {
  project       = "k8s"
  instance_name = "k8s-worker-node"
  vpc_id        = "vpc-0aedda8091caa685a"
  ami_id        = "ami-024e6efaf93d85776"
  worker_fqdn   = "worker.k8s.internal"
  tags = {
    Project   = local.project
    Role      = "worker-node"
    ManagedBy = "Terraform"
  }
}

module "network" {
  source = "../../modules/network-data"
  vpc_id = local.vpc_id
}

data "terraform_remote_state" "masters" {
  backend = "local"
  config  = { path = "../../state/puppet-masters.tfstate" }
}

data "terraform_remote_state" "cp" {
  backend = "local"
  config  = { path = "../../state/k8s-control-pane.tfstate" }
}

data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# IAM role: read-only on the SSM join parameter
# -----------------------------------------------------------------------------
resource "aws_iam_role" "wk" {
  name = "k8s-worker-node-role"
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

resource "aws_iam_role_policy" "wk_ssm" {
  name = "k8s-worker-ssm-join"
  role = aws_iam_role.wk.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameter", "ssm:GetParameters"]
      Resource = [
        "arn:aws:ssm:us-east-2:${data.aws_caller_identity.current.account_id}:parameter${data.terraform_remote_state.cp.outputs.ssm_join_param}",
        "arn:aws:ssm:us-east-2:${data.aws_caller_identity.current.account_id}:parameter/puppet/*",
      ]
    }]
  })
}

resource "aws_iam_instance_profile" "wk" {
  name = "k8s-worker-node-profile"
  role = aws_iam_role.wk.name
}

# -----------------------------------------------------------------------------
# Security group: SSH via EICE only
# -----------------------------------------------------------------------------
resource "aws_security_group" "this" {
  name        = "${local.instance_name}-sg"
  description = "k8s worker SG (private)"
  vpc_id      = local.vpc_id

  ingress {
    description     = "SSH via EC2 Instance Connect Endpoint"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [data.terraform_remote_state.cp.outputs.eice_security_group]
  }
  ingress {
    description = "kubelet"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  ingress {
    description = "Flannel VXLAN"
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  ingress {
    description = "NodePort"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.instance_name}-sg" })
}

# Commented out - puppet-master not deployed
# resource "aws_security_group_rule" "to_puppet_master" {
#   type                     = "ingress"
#   security_group_id        = data.terraform_remote_state.masters.outputs.ec2_security_group_id
#   protocol                 = "tcp"
#   from_port                = 8140
#   to_port                  = 8140
#   source_security_group_id = aws_security_group.this.id
#   description              = "k8s-worker to puppet-master 8140"
# }

resource "aws_security_group_rule" "to_control_api" {
  type                     = "ingress"
  security_group_id        = data.terraform_remote_state.cp.outputs.security_group_id
  protocol                 = "tcp"
  from_port                = 6443
  to_port                  = 6443
  source_security_group_id = aws_security_group.this.id
  description              = "k8s-worker to control-plane API 6443"
}

resource "aws_security_group_rule" "to_control_flannel" {
  type                     = "ingress"
  security_group_id        = data.terraform_remote_state.cp.outputs.security_group_id
  protocol                 = "udp"
  from_port                = 8472
  to_port                  = 8472
  source_security_group_id = aws_security_group.this.id
  description              = "k8s-worker Flannel VXLAN to control-plane"
}

# -----------------------------------------------------------------------------
# EC2 instance (private, no public IP)
# -----------------------------------------------------------------------------
resource "aws_instance" "this" {
  ami                         = local.ami_id
  instance_type               = "t3.medium"
  subnet_id                   = module.network.private_subnet_ids[length(module.network.private_subnet_ids) > 1 ? 1 : 0]
  vpc_security_group_ids      = [aws_security_group.this.id]
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.wk.name

  user_data = base64encode(templatefile("${path.module}/user-data/k8s-worker.sh.tftpl", {
    node_name      = local.instance_name
    worker_fqdn    = local.worker_fqdn
    ssm_join_param = data.terraform_remote_state.cp.outputs.ssm_join_param
    puppet_master  = "puppet-master.internal"  # Placeholder - puppet-master not deployed
  }))
  user_data_replace_on_change = true

  root_block_device {
    volume_size           = 40
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  tags = merge(local.tags, {
    Name = local.instance_name
    Role = "k8s-worker"
  })

  depends_on = [
    # aws_security_group_rule.to_puppet_master,  # Commented out - puppet-master not deployed
    aws_security_group_rule.to_control_api,
    aws_security_group_rule.to_control_flannel,
  ]
}

resource "aws_route53_record" "wk" {
  zone_id = data.terraform_remote_state.cp.outputs.private_zone_id
  name    = local.worker_fqdn
  type    = "A"
  ttl     = 60
  records = [aws_instance.this.private_ip]
}

output "instance_id"       { value = aws_instance.this.id }
output "private_ip"        { value = aws_instance.this.private_ip }
output "private_fqdn"      { value = local.worker_fqdn }
output "security_group_id" { value = aws_security_group.this.id }
