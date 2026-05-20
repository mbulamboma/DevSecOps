# =============================================================================
# Kubernetes Control-Plane node (single EC2, PRIVATE subnet)
#
# Design:
#   - Private subnet, NO public IP, NO inbound SSH from internet
#   - SSH only via EC2 Instance Connect Endpoint (EICE)
#   - This stack also creates shared resources used by the worker:
#       * EC2 Instance Connect Endpoint (one per VPC)
#       * Route53 private hosted zone "k8s.internal"
#       * Private DNS A record: cp.k8s.internal -> private IP
#   - IAM role lets puppet-managed kubeadm publish the join command to SSM
#     Parameter Store; the worker reads it from there.
#   - user-data does the bare minimum: hostname + install puppet-agent +
#     kick off the first run. Containerd, kubeadm init, Flannel etc are all
#     installed by Puppet manifests in the GitHub control-repo.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.60" }
  }
  backend "local" {
    path = "../../state/k8s-control-pane.tfstate"
  }
}

provider "aws" {
  region = "us-east-2"
}

locals {
  project        = "k8s"
  instance_name  = "k8s-control-plane"
  vpc_id         = "vpc-0aedda8091caa685a"
  ami_id         = "ami-024e6efaf93d85776"
  private_zone   = "k8s.internal"
  cp_fqdn        = "cp.k8s.internal"
  ssm_join_param = "/k8s/join-command"
  tags = {
    Project   = local.project
    Role      = "control-plane"
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

data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# Route53 private hosted zone (on-prem-like internal DNS)
# -----------------------------------------------------------------------------
resource "aws_route53_zone" "internal" {
  name = local.private_zone
  vpc {
    vpc_id = local.vpc_id
  }
  tags = merge(local.tags, { Name = local.private_zone })
}

# -----------------------------------------------------------------------------
# EC2 Instance Connect Endpoint (single VPC-wide endpoint)
# -----------------------------------------------------------------------------
resource "aws_security_group" "eice" {
  name        = "eice-endpoint-sg"
  description = "EC2 Instance Connect Endpoint egress to private nodes"
  vpc_id      = local.vpc_id

  egress {
    description = "SSH to VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  tags = merge(local.tags, { Name = "eice-endpoint-sg" })
}

resource "aws_ec2_instance_connect_endpoint" "this" {
  subnet_id          = module.network.private_subnet_ids[0]
  security_group_ids = [aws_security_group.eice.id]
  preserve_client_ip = false
  tags               = merge(local.tags, { Name = "vpc-eice" })
}

# -----------------------------------------------------------------------------
# IAM role: lets the control-plane node publish the kubeadm join command
# -----------------------------------------------------------------------------
resource "aws_iam_role" "cp" {
  name = "k8s-control-plane-role"
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

resource "aws_iam_role_policy" "cp_ssm" {
  name = "k8s-cp-ssm-join"
  role = aws_iam_role.cp.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:GetParameter",
          "ssm:DeleteParameter",
          "ssm:AddTagsToResource"
        ]
        Resource = "arn:aws:ssm:us-east-2:${data.aws_caller_identity.current.account_id}:parameter${local.ssm_join_param}"
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = "arn:aws:ssm:us-east-2:${data.aws_caller_identity.current.account_id}:parameter/puppet/*"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances", "ec2:DescribeTags"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "cp" {
  name = "k8s-control-plane-profile"
  role = aws_iam_role.cp.name
}

# -----------------------------------------------------------------------------
# Security group: no public SSH; ingress from VPC + EICE only
# -----------------------------------------------------------------------------
resource "aws_security_group" "this" {
  name        = "${local.instance_name}-sg"
  description = "k8s control-plane SG (private)"
  vpc_id      = local.vpc_id

  ingress {
    description     = "SSH via EC2 Instance Connect Endpoint"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.eice.id]
  }
  ingress {
    description = "k8s API"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  ingress {
    description = "etcd peer/client"
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    self        = true
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

locals {
  masters_sg_id = try(data.terraform_remote_state.masters.outputs.ec2_security_group_id, "")
}

resource "aws_security_group_rule" "to_puppet_master" {
  count                    = local.masters_sg_id != "" ? 1 : 0
  type                     = "ingress"
  security_group_id        = local.masters_sg_id
  protocol                 = "tcp"
  from_port                = 8140
  to_port                  = 8140
  source_security_group_id = aws_security_group.this.id
  description              = "k8s-control to puppet-master 8140"
}

# -----------------------------------------------------------------------------
# EC2 instance (private, no public IP)
# -----------------------------------------------------------------------------
resource "aws_instance" "this" {
  ami                         = local.ami_id
  instance_type               = "t3.medium"
  subnet_id                   = module.network.private_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.this.id]
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.cp.name

  user_data = base64encode(templatefile("${path.module}/user-data/k8s-control.sh.tftpl", {
    node_name      = local.instance_name
    cp_fqdn        = local.cp_fqdn
    ssm_join_param = local.ssm_join_param
    puppet_master  = data.terraform_remote_state.masters.outputs.alb_dns_name
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
    Name          = local.instance_name
    Role          = "k8s-control-plane"
    K8sJoinHelper = "true"
  })

  depends_on = [
    aws_security_group_rule.to_puppet_master,
    aws_ec2_instance_connect_endpoint.this,
  ]
}

resource "aws_route53_record" "cp" {
  zone_id = aws_route53_zone.internal.zone_id
  name    = local.cp_fqdn
  type    = "A"
  ttl     = 60
  records = [aws_instance.this.private_ip]
}

# -----------------------------------------------------------------------------
# Outputs (consumed by k8s-worker-node stack)
# -----------------------------------------------------------------------------
output "instance_id"         { value = aws_instance.this.id }
output "private_ip"          { value = aws_instance.this.private_ip }
output "private_dns_aws"     { value = aws_instance.this.private_dns }
output "private_fqdn"        { value = local.cp_fqdn }
output "security_group_id"   { value = aws_security_group.this.id }
output "eice_security_group" { value = aws_security_group.eice.id }
output "eice_endpoint_id"    { value = aws_ec2_instance_connect_endpoint.this.id }
output "private_zone_id"     { value = aws_route53_zone.internal.zone_id }
output "private_zone_name"   { value = aws_route53_zone.internal.name }
output "ssm_join_param"      { value = local.ssm_join_param }
