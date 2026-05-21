# PuppetDB Stack

Stack Terraform pour déployer PuppetDB sur AWS avec ALB interne et base PostgreSQL RDS.

## Description

Déploie une infrastructure PuppetDB complète avec stockage PostgreSQL dédié. Premier stack à déployer car il crée la base RDS partagée avec Foreman.

## Architecture

- **ALB interne** : HTTP:8080, health check `/pdb/meta/v1/version`
- **ASG** : 1-2 instances t3.medium dans les subnets publics
- **RDS** : PostgreSQL dédié pour le stockage PuppetDB

## Ressources créées

| Module | Ressource | Description |
|--------|-----------|-------------|
| `network` | Data source | Récupère les subnets du VPC |
| `rds` | RDS PostgreSQL | Instance `puppetdb-pg`, DB `puppetdb` |
| `alb` | ALB interne | Port 8080, health check PuppetDB |
| `asg` | Auto Scaling Group | min=1, max=2, desired=1 |

## Variables

| Variable | Type | Description |
|----------|------|-------------|
| `rds_password` | string (sensitive) | Mot de passe RDS, via `TF_VAR_rds_password` |

## Configuration

| Paramètre | Valeur |
|-----------|--------|
| VPC ID | `vpc-0aedda8091caa685a` |
| AMI | `ami-024e6efaf93d85776` (Ubuntu) |
| Key | `k8s-key` |
| RDS User | `puppetadmin` |
| App Port | `8080` |

## Outputs

| Output | Description |
|--------|-------------|
| `alb_dns_name` | DNS de l'ALB interne |
| `alb_security_group_id` | SG de l'ALB |
| `ec2_security_group_id` | SG des instances |
| `rds_endpoint` | Endpoint RDS PostgreSQL |
| `rds_security_group_id` | SG du RDS |

## Dépendances

Aucune - c'est le premier stack à déployer.

## Déploiement

```bash
cd aws/puppetdb
export TF_VAR_rds_password="xxx"
terraform init
terraform apply
```
