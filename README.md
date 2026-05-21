# DevSecOps Infrastructure - Puppet + Kubernetes on AWS

Infrastructure as Code pour déployer un stack DevSecOps complet sur AWS avec Puppet et Kubernetes.

## Composants

- **Foreman** - Interface web pour gérer les nodes Puppet (ENC)
- **Puppet Server** - Gestion de configuration avec r10k (GitOps)
- **PuppetDB** - Stockage des facts et rapports Puppet
- **Kubernetes** - Cluster K8s (control-plane + workers)

## Architecture

![Architecture](aws/diagrams/Overview/overview.png)

| Couche | Composants | Accès |
|--------|------------|-------|
| Public | Foreman ALB, K8s Apps ALB | Internet (HTTPS) |
| Interne | Puppet Server ALB, PuppetDB ALB | VPC uniquement |
| Privé | K8s Control Plane, Workers | Pas d'accès internet direct |
| Data | RDS PostgreSQL | Sous-réseaux privés |

## Documentation

| Document | Description |
|----------|-------------|
| [Foreman](docs/foreman.md) | Stack Foreman (ALB, ASG, DNS) |
| [Puppet Server](docs/puppet-server.md) | Stack Puppet Server avec r10k |
| [PuppetDB](docs/puppetdb.md) | Stack PuppetDB et RDS |
| [Kubernetes](docs/kubernetes.md) | Stacks K8s control-plane et workers |
| [Modules](docs/modules.md) | Modules Terraform réutilisables |

## Diagrammes

| Diagramme | Description |
|-----------|-------------|
| [Architecture détaillée](aws/diagrams/detailed/architecture.png) | Tous les composants |
| [Réseau](aws/diagrams/Overview/network-overview.png) | VPC et subnets |
| [Flux de données](aws/diagrams/Overview/data-flow-overview.png) | Flux entre composants |
| [GitOps](aws/diagrams/detailed/gitops-flow.png) | Workflow r10k |
| [Sécurité](aws/diagrams/detailed/security-flow.png) | Patterns de sécurité |

## GitOps

```
Dev → git push → GitHub → r10k (60s) → Puppet Server → Agents
```

Le control-repo Puppet est la source de vérité pour toute la config.

## Sécurité

- Pas de SSH public - accès via EC2 Instance Connect Endpoint
- Sous-réseaux privés pour K8s avec NAT Gateway
- Certificats ACM pour HTTPS
- Security Groups least-privilege
- Rôles IAM (pas de credentials hardcodés)
- SSM Parameter Store pour les secrets

## Structure

```
DevSecOps/
├── aws/
│   ├── diagrams/           # Diagrammes d'architecture
│   ├── foreman/            # Stack Terraform Foreman
│   ├── puppet-masters/     # Stack Terraform Puppet Server
│   ├── puppetdb/           # Stack Terraform PuppetDB
│   ├── puppet-slaves/      # Stacks K8s nodes
│   └── modules/            # Modules Terraform réutilisables
├── docs/                   # Documentation détaillée
└── terraform-onpremise-tests/
```

## Déploiement

### Prérequis

- Terraform >= 1.5.0
- AWS CLI configuré
- Python 3.8+ (pour les diagrammes)

### Config AWS

```bash
export AWS_ACCESS_KEY_ID="xxx"
export AWS_SECRET_ACCESS_KEY="xxx"
export AWS_DEFAULT_REGION="us-east-2"
```

### Ordre de déploiement

1. PuppetDB (crée RDS)
2. Puppet Server
3. Foreman
4. K8s Control Plane
5. K8s Workers

```bash
cd aws/puppetdb && terraform init && terraform apply
cd aws/puppet-masters && terraform init && terraform apply
cd aws/foreman && terraform init && terraform apply
cd aws/puppet-slaves/k8s-control-pane && terraform init && terraform apply
cd aws/puppet-slaves/k8s-worker-node && terraform init && terraform apply
```

## Variables

```bash
export TF_VAR_rds_password="xxx"
export TF_VAR_foreman_admin_password="xxx"
```

## Générer les diagrammes

```bash
pip install diagrams
cd aws/diagrams/Overview && python overview.py
cd aws/diagrams/detailed && python architecture.py
```

## Auteur

Mbula Mboma - [@mbulamboma](https://github.com/mbulamboma)

## Licence

MIT
