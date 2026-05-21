# Puppet Server Stack

Stack Terraform déployant Puppet Server 7 sur AWS avec GitOps via r10k.

## Description

Le serveur publie son IP privée dans SSM Parameter Store car les agents Puppet doivent communiquer directement (mTLS sur port 8140 incompatible avec ALB layer-7).

## Architecture

- **ALB interne** : HTTP:8140, usage limité (dashboards/outils uniquement)
- **ASG** : min=1, max=2, desired=1, instances t3.medium
- **GitOps** : r10k pull du control repo toutes les minutes (cron)
- **PuppetDB** : connexion via ALB interne du stack puppetdb (port 8080)

## Ressources créées

| Ressource | Type | Description |
|-----------|------|-------------|
| ALB | Module interne | Load balancer privé (10.0.0.0/16) |
| ASG | Module | EC2 puppetserver, health check EC2 only |
| IAM Role | `aws_iam_role` | Assume role EC2 |
| IAM Policy | `aws_iam_role_policy` | SSM put/get /puppet/*, EC2 describe |
| Instance Profile | `aws_iam_instance_profile` | Attaché à l'ASG |
| SG Rule | `aws_security_group_rule` | Ingress TCP 8080 vers PuppetDB ALB |

## Variables

| Variable | Type | Description |
|----------|------|-------------|
| `github_token` | string (sensitive) | Token pour cloner le control repo |

## Outputs

| Output | Description |
|--------|-------------|
| `alb_dns_name` | DNS de l'ALB interne |
| `ec2_security_group_id` | SG des instances |

## Dépendances

- Stack **puppetdb** (ALB interne)
- Control repo GitHub configuré
- VPC et subnets existants

## GitOps

Le Puppet Server utilise r10k pour synchroniser la configuration depuis GitHub :

```
GitHub (control-repo) → r10k (cron 60s) → /etc/puppetlabs/code/environments/
```

## Déploiement

```bash
cd aws/puppet-masters
export TF_VAR_github_token="xxx"
terraform init
terraform apply
```
