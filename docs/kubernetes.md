# Kubernetes Stacks

Stacks Terraform pour déployer un cluster Kubernetes 1.30 sur AWS.

## k8s-control-pane

Déploie un nœud control-plane Kubernetes en subnet privé.

### Ressources créées

| Ressource | Type | Description |
|-----------|------|-------------|
| EC2 | `aws_instance` | t3.medium, 40GB gp3 chiffré |
| Route53 Zone | `aws_route53_zone` | Zone privée `k8s.internal` |
| DNS Record | `aws_route53_record` | A record `cp.k8s.internal` |
| EICE | `aws_ec2_instance_connect_endpoint` | SSH sans IP publique |
| Security Group | `aws_security_group` | Ports K8s (6443, 2379-2380, 10250, 8472/udp, 30000-32767) |
| IAM Role | `aws_iam_role` | Permissions SSM pour publier join command |

### Configuration

| Paramètre | Valeur |
|-----------|--------|
| VPC ID | `vpc-0aedda8091caa685a` |
| AMI | `ami-024e6efaf93d85776` (Ubuntu 22.04) |
| Zone privée | `k8s.internal` |
| FQDN | `cp.k8s.internal` |
| SSM Param | `/k8s/join-command` |

### Outputs

- `instance_id`, `private_ip`, `private_dns_aws`, `private_fqdn`
- `security_group_id`, `eice_security_group`, `eice_endpoint_id`
- `private_zone_id`, `private_zone_name`, `ssm_join_param`

---

## k8s-worker-node

Déploie des workers Kubernetes qui rejoignent automatiquement le cluster.

### Ressources créées

| Ressource | Type | Description |
|-----------|------|-------------|
| EC2 | `aws_instance` | t3.medium, 40GB gp3 chiffré |
| DNS Record | `aws_route53_record` | A record `wk.k8s.internal` |
| Security Group | `aws_security_group` | Ports worker (10250, 8472/udp, 30000-32767) |
| IAM Role | `aws_iam_role` | Permissions SSM pour lire join command |

### Configuration

| Paramètre | Valeur |
|-----------|--------|
| FQDN | `wk.k8s.internal` |
| SSM Param | `/k8s/join-command` (lecture) |

### Outputs

- `instance_id`, `private_ip`, `private_fqdn`
- `security_group_id`

---

## Dépendances

| Stack | Dépend de |
|-------|-----------|
| k8s-control-pane | Puppet Server (pour puppet-agent) |
| k8s-worker-node | k8s-control-pane (join command dans SSM) |

## Déploiement

```bash
# Control Plane d'abord
cd aws/puppet-slaves/k8s-control-pane
terraform init
terraform apply

# Workers ensuite
cd aws/puppet-slaves/k8s-worker-node
terraform init
terraform apply
```

## Accès SSH via EICE

```bash
aws ec2-instance-connect ssh --instance-id i-xxx --connection-type eice
```
