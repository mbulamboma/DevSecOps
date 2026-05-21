# Foreman Stack

Stack Terraform pour déployer Foreman 3.12 sur AWS.

## Description

Expose une interface web HTTPS via ALB public sur `foreman.emlinkapp.com`. Utilise la base PostgreSQL RDS partagée avec le stack PuppetDB.

## Architecture

- **ALB public** : HTTPS (port 443) avec certificat ACM
- **ASG** : 1-2 instances t3.medium (Ubuntu 22.04)
- **DNS** : Route53 alias vers l'ALB
- **Base de données** : RDS PostgreSQL externe (stack puppetdb)

## Ressources créées

| Ressource | Module/Type | Description |
|-----------|-------------|-------------|
| ALB | `../modules/alb` | Load balancer HTTPS public |
| ASG | `../modules/asg` | Auto Scaling Group avec EC2 |
| DNS | `../modules/route53-alias` | Enregistrement DNS foreman.emlinkapp.com |
| SG Rule | `aws_security_group_rule` | Accès Foreman → RDS (port 5432) |

## Variables

| Variable | Type | Description |
|----------|------|-------------|
| `rds_password` | string (sensitive) | Mot de passe RDS PostgreSQL |
| `foreman_admin_password` | string (sensitive) | Mot de passe admin Foreman |

## Outputs

| Output | Description |
|--------|-------------|
| `alb_dns_name` | DNS name de l'ALB |
| `fqdn` | FQDN complet (foreman.emlinkapp.com) |

## Dépendances

- Stack **puppetdb** (RDS PostgreSQL)
- Certificat ACM existant
- VPC et subnets existants

## Déploiement

```bash
cd aws/foreman
export TF_VAR_rds_password="xxx"
export TF_VAR_foreman_admin_password="xxx"
terraform init
terraform apply
```
