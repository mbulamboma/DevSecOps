# Modules Terraform

Modules réutilisables pour l'infrastructure AWS.

## alb

Application Load Balancer générique. Supporte mode public/interne, HTTPS/HTTP, sticky sessions, redirection HTTP→HTTPS.

### Inputs

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `name` | string | - | Nom du ALB |
| `vpc_id` | string | - | VPC ID |
| `subnet_ids` | list(string) | - | Subnets pour le ALB |
| `internal` | bool | `false` | ALB interne ou public |
| `ingress_cidrs` | list(string) | `["0.0.0.0/0"]` | CIDRs autorisés |
| `listener_protocol` | string | `"HTTPS"` | HTTPS ou HTTP |
| `listener_port` | number | `443` | Port du listener |
| `certificate_arn` | string | `null` | ARN certificat ACM |
| `redirect_http_to_https` | bool | `true` | Redirection 80→443 |
| `target_port` | number | `443` | Port cible |
| `target_protocol` | string | `"HTTPS"` | Protocole cible |
| `health_check_path` | string | `"/"` | Path health check |
| `health_check_matcher` | string | `"200-399"` | Codes HTTP valides |
| `stickiness` | bool | `true` | Sticky sessions |
| `stickiness_duration` | number | `86400` | Durée cookie (sec) |

### Outputs

| Output | Description |
|--------|-------------|
| `alb_arn` | ARN du ALB |
| `alb_dns_name` | DNS name |
| `alb_zone_id` | Zone ID Route53 |
| `target_group_arn` | ARN du target group |
| `security_group_id` | SG du ALB |

---

## asg

Auto Scaling Group avec launch template.

### Inputs

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `name` | string | - | Nom de l'ASG |
| `ami_id` | string | - | AMI ID |
| `instance_type` | string | `"t3.medium"` | Type d'instance |
| `key_name` | string | - | Clé SSH |
| `vpc_id` | string | - | VPC ID |
| `subnet_ids` | list(string) | - | Subnets |
| `min_size` | number | `1` | Taille min |
| `max_size` | number | `2` | Taille max |
| `desired_capacity` | number | `1` | Capacité désirée |
| `target_group_arns` | list(string) | `[]` | Target groups ALB |
| `user_data` | string | `""` | Script user-data |
| `iam_instance_profile` | string | `null` | Instance profile |
| `ingress_rules` | list(object) | `[]` | Règles SG ingress |

### Outputs

| Output | Description |
|--------|-------------|
| `asg_name` | Nom de l'ASG |
| `asg_arn` | ARN de l'ASG |
| `security_group_id` | SG des instances |
| `launch_template_id` | ID du launch template |

---

## network-data

Data source pour récupérer les infos réseau du VPC.

### Inputs

| Variable | Type | Description |
|----------|------|-------------|
| `vpc_id` | string | VPC ID |

### Outputs

| Output | Description |
|--------|-------------|
| `vpc_id` | VPC ID |
| `public_subnet_ids` | IDs des subnets publics |
| `private_subnet_ids` | IDs des subnets privés |
| `availability_zones` | AZs disponibles |

---

## rds-postgres

Instance RDS PostgreSQL.

### Inputs

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `identifier` | string | - | Identifiant RDS |
| `db_name` | string | - | Nom de la base |
| `username` | string | - | Utilisateur admin |
| `password` | string | - | Mot de passe |
| `vpc_id` | string | - | VPC ID |
| `subnet_ids` | list(string) | - | Subnets |
| `instance_class` | string | `"db.t3.micro"` | Classe d'instance |
| `allocated_storage` | number | `20` | Stockage (GB) |
| `engine_version` | string | `"15"` | Version PostgreSQL |
| `multi_az` | bool | `false` | Multi-AZ |
| `skip_final_snapshot` | bool | `true` | Skip snapshot final |

### Outputs

| Output | Description |
|--------|-------------|
| `endpoint` | Endpoint RDS |
| `port` | Port (5432) |
| `security_group_id` | SG du RDS |

---

## route53-alias

Enregistrement DNS alias vers un ALB.

### Inputs

| Variable | Type | Description |
|----------|------|-------------|
| `zone_id` | string | Zone ID Route53 |
| `name` | string | Nom DNS (ex: foreman) |
| `alb_dns_name` | string | DNS name de l'ALB |
| `alb_zone_id` | string | Zone ID de l'ALB |

### Outputs

| Output | Description |
|--------|-------------|
| `fqdn` | FQDN complet |
