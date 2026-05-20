# DevSecOps Infrastructure - Puppet + Kubernetes on AWS

[![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.5.0-623CE4?logo=terraform)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-us--east--2-FF9900?logo=amazon-aws)](https://aws.amazon.com/)
[![Puppet](https://img.shields.io/badge/Puppet-8.x-FFAE1A?logo=puppet)](https://puppet.com/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.29-326CE5?logo=kubernetes)](https://kubernetes.io/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A production-ready **Infrastructure as Code (IaC)** project that deploys a complete DevSecOps stack on AWS, featuring:

- 🎭 **Foreman** - Web UI for Puppet node management and ENC (External Node Classifier)
- 🐙 **Puppet Master** - Configuration management with r10k GitOps workflow
- 📊 **PuppetDB** - Centralized storage for Puppet facts and reports
- ☸️ **Kubernetes** - Managed K8s cluster (control-plane + worker nodes)
- 🔐 **Security-first** - Private subnets, ALBs, ACM certificates, EICE for SSH-less access

---

## 📐 Architecture Overview

<p align="center">
  <img src="aws/diagrams/Overview/overview.png" alt="Architecture Overview" width="800">
</p>

| Layer | Components | Access |
|-------|------------|--------|
| **Public** | Foreman ALB, Web App ALB | Internet-facing (HTTPS) |
| **Internal** | Puppet Master ALB, PuppetDB ALB | VPC internal only |
| **Private** | K8s Control Plane, Worker Nodes | No direct internet access |
| **Data** | RDS PostgreSQL | Private subnets only |

### 📊 Additional Diagrams

| Diagram | Description |
|---------|-------------|
| [Detailed Architecture](aws/diagrams/detailed/architecture.png) | Complete infrastructure with all components |
| [Network Topology](aws/diagrams/Overview/network-overview.png) | VPC, subnets, and network flow |
| [Data Flow](aws/diagrams/Overview/data-flow-overview.png) | How data moves through the system |
| [GitOps Flow](aws/diagrams/detailed/gitops-flow.png) | r10k and Puppet deployment workflow |
| [Security Flow](aws/diagrams/detailed/security-flow.png) | Security architecture and access patterns |

---

## 🏗️ Stack Components

### Foreman Stack
- **Public ALB** with HTTPS (ACM certificate)
- **Auto Scaling Group** (min: 1, max: 2)
- Connects to shared RDS PostgreSQL
- DNS: `foreman.emlinkapp.com`

➡️ [View Foreman Diagram](aws/diagrams/detailed/foreman-stack.png)

### Puppet Masters Stack
- **Internal ALB** on port 8140
- **r10k** syncs from GitHub control-repo every 60 seconds
- Manages all Puppet agents (K8s nodes)

➡️ [View Puppet Masters Diagram](aws/diagrams/detailed/puppet-masters-stack.png)

### PuppetDB Stack
- **Internal ALB** on port 8081
- Stores facts, catalogs, and reports
- Shared RDS PostgreSQL backend

➡️ [View PuppetDB Diagram](aws/diagrams/detailed/puppetdb-stack.png)

### Kubernetes Stack
- **Control Plane**: kubeadm-initialized, etcd, Flannel CNI
- **Worker Nodes**: Auto-join via SSM Parameter Store
- **NodePort Services**: Exposed via public ALB

➡️ [View Kubernetes Diagram](aws/diagrams/detailed/k8s-stack.png)

---

## 🔄 GitOps Workflow

```
Developer → git push → GitHub (control-repo) → r10k pull (60s) → Puppet Master → Agents
```

The Puppet control repository is the **single source of truth** for all infrastructure configuration.

---

## 🔐 Security Features

- ✅ **No public SSH** - All access via EC2 Instance Connect Endpoint (EICE)
- ✅ **Private subnets** for K8s nodes with NAT Gateway egress
- ✅ **ACM certificates** for HTTPS termination
- ✅ **Security Groups** with least-privilege access
- ✅ **IAM roles** for EC2 instances (no hardcoded credentials)
- ✅ **SSM Parameter Store** for secrets (K8s join token)

---

## 📁 Project Structure

```
DevSecOps/
├── aws/
│   ├── diagrams/                    # Architecture diagrams (Python + PNG)
│   │   ├── detailed/                # Detailed component diagrams
│   │   └── Overview/                # High-level overview diagrams
│   ├── foreman/                     # Foreman Terraform stack
│   ├── puppet-masters/              # Puppet Master Terraform stack
│   ├── puppetdb/                    # PuppetDB Terraform stack
│   ├── puppet-slaves/               # K8s nodes Terraform stacks
│   │   ├── k8s-control-pane/
│   │   └── k8s-worker-node/
│   └── modules/                     # Reusable Terraform modules
│       ├── alb/
│       ├── asg/
│       ├── network-data/
│       ├── rds-postgres/
│       └── route53-alias/
├── terraform-onpremise-tests/       # On-premise VMware testing
└── README.md
```

---

## 🚀 Getting Started

### Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.5.0
- [AWS CLI](https://aws.amazon.com/cli/) configured with appropriate credentials
- [Python 3.8+](https://www.python.org/) (for diagram generation)

### AWS Credentials Setup

```bash
# Option 1: Environment Variables (Recommended)
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-east-2"

# Option 2: AWS CLI Profile
aws configure --profile devsecops
export AWS_PROFILE=devsecops
```

### Deployment Order

The stacks must be deployed in this order due to dependencies:

1. **PuppetDB** (creates RDS, shared by Foreman)
2. **Puppet Masters** (depends on PuppetDB ALB)
3. **Foreman** (depends on PuppetDB RDS)
4. **K8s Control Plane** (depends on Puppet Master)
5. **K8s Worker Nodes** (depends on Control Plane)

```bash
# Deploy individually
cd aws/puppetdb && terraform init && terraform apply
cd aws/puppet-masters && terraform init && terraform apply
cd aws/foreman && terraform init && terraform apply
cd aws/puppet-slaves/k8s-control-pane && terraform init && terraform apply
cd aws/puppet-slaves/k8s-worker-node && terraform init && terraform apply
```

---

## 🔧 Configuration

### Terraform Variables

```bash
# Set via environment variable
export TF_VAR_rds_password="your-secure-password"
export TF_VAR_foreman_admin_password="your-admin-password"

# Or via command line
terraform apply -var="rds_password=xxx" -var="foreman_admin_password=xxx"
```

### Puppet Control Repository

The Puppet Master syncs from a GitHub control repository using r10k:
- Repository: `github.com/mbulamboma/devsecops-puppet-control`
- Branch: `production`

---

## 📊 Generating Diagrams

```bash
pip install diagrams

# Generate diagrams
cd aws/diagrams/Overview && python overview.py
cd aws/diagrams/detailed && python architecture.py
```

---

## 🛡️ Security Checklist

| File Pattern | Status | Notes |
|--------------|--------|-------|
| `*.pem` | 🚫 Ignored | SSH private keys |
| `*.tfstate` | 🚫 Ignored | Terraform state |
| `secrets.yml` | 🚫 Ignored | AWS credentials |
| `*.tfvars` | 🚫 Ignored | Variable files |
| `*.log` | 🚫 Ignored | Log files |

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 👤 Author

**Mbula Mboma** - [@mbulamboma](https://github.com/mbulamboma)

---

## 🙏 Acknowledgments

- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)
- [Puppet Documentation](https://puppet.com/docs/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Diagrams Library](https://diagrams.mingrammer.com/)
