"""
Detailed - Security posture across the stack (live).

Highlights:
  - No public SSH on any instance: SSH happens via EC2 Instance Connect
    Endpoint (EICE eice-0d901a8144ab2e126) with IAM-scoped access.
  - K8s nodes live in private subnets (no public IP), egress via NAT.
  - SSM session manager + parameter store used for join-command bootstrap
    via IAM role on EC2 (no static creds).
  - Puppet master autosign policy: only hostnames matching k8s-* are
    auto-signed; everything else requires manual `puppetserver ca sign`.
  - SG chain enforces zero-trust between tiers.
"""

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.management import SystemsManager as SSM
from diagrams.aws.security import IAMPermissions, IAMRole
from diagrams.aws.network import VPC
from diagrams.onprem.client import Users


graph_attr = {"fontsize": "14", "labelloc": "t", "pad": "0.5"}

with Diagram(
    "Security posture - EICE, SSM, autosign, SG chain (live)",
    filename="security-flow",
    show=False,
    direction="LR",
    graph_attr=graph_attr,
):
    admin = Users("Admin\n(IAM user)")
    internet = Users("Internet 0.0.0.0/0")
    vpc_cidr = VPC("VPC 10.0.0.0/16")

    with Cluster("Access plane (no public SSH)"):
        eice = IAMPermissions(
            "EICE eice-0d901a8144ab2e126\nSSH :22 tunnel\nIAM-scoped, audited"
        )
        ssm = SSM(
            "SSM Session Manager\n+ Parameter Store\n/k8s/join-command (SecureString)"
        )
        iam_ec2 = IAMRole(
            "EC2 instance profile\n- ssm:GetParameter\n- ssm:PutParameter\n- ssmmessages:*"
        )

    with Cluster("Foreman (public tier)"):
        sg_fm_alb = IAMPermissions("SG Foreman ALB\nin :80, :443 <- 0.0.0.0/0")
        sg_fm_ec2 = IAMPermissions(
            "SG Foreman EC2\nin :443 <- SG Foreman ALB\nin :22 <- EICE only"
        )

    with Cluster("Puppet Master (internal tier)"):
        sg_pm_alb = IAMPermissions("SG Master ALB\nin :8140 <- 10.0.0.0/16")
        sg_pm_ec2 = IAMPermissions(
            "SG Master EC2\nin :8140 <- SG Master ALB\nin :22 <- EICE only"
        )
        autosign = IAMPermissions(
            "autosign policy\nallow: k8s-*\ndeny:  everything else"
        )

    with Cluster("PuppetDB (internal tier)"):
        sg_pdb_alb = IAMPermissions("SG PuppetDB ALB\nin :8080 <- 10.0.0.0/16")
        sg_pdb_ec2 = IAMPermissions(
            "SG PuppetDB EC2\nin :8080 <- SG PuppetDB ALB\nin :22 <- EICE only"
        )

    with Cluster("Kubernetes (private subnets, no public IP)"):
        sg_k8s = IAMPermissions(
            "SG k8s nodes\nin :6443, :10250 intra-cluster\nin :30080 <- SG web ALB\nin :22 <- EICE only"
        )
        sg_web_alb = IAMPermissions("SG web ALB\nin :80 <- 0.0.0.0/0")

    with Cluster("Data"):
        sg_rds = IAMPermissions("SG RDS\nin :5432 <- SG Foreman EC2, SG PuppetDB EC2")

    # Public exposure
    internet >> Edge(label=":80, :443") >> sg_fm_alb >> Edge(label=":443") >> sg_fm_ec2
    internet >> Edge(label=":80") >> sg_web_alb >> Edge(label=":30080") >> sg_k8s

    # Internal east-west
    vpc_cidr >> Edge(label=":8140") >> sg_pm_alb >> Edge(label=":8140") >> sg_pm_ec2
    vpc_cidr >> Edge(label=":8080") >> sg_pdb_alb >> Edge(label=":8080") >> sg_pdb_ec2
    sg_fm_ec2 >> Edge(label=":8140 ENC") >> sg_pm_alb
    sg_pm_ec2 >> Edge(label=":8080 facts") >> sg_pdb_alb
    sg_k8s >> Edge(label=":8140 agent") >> sg_pm_alb

    # DB
    sg_fm_ec2 >> Edge(label=":5432") >> sg_rds
    sg_pdb_ec2 >> Edge(label=":5432") >> sg_rds

    # SSH via EICE (no public :22)
    admin >> Edge(label="aws ec2-instance-connect\nssh (IAM)") >> eice
    eice >> Edge(style="dashed", label=":22") >> sg_fm_ec2
    eice >> Edge(style="dashed", label=":22") >> sg_pm_ec2
    eice >> Edge(style="dashed", label=":22") >> sg_pdb_ec2
    eice >> Edge(style="dashed", label=":22") >> sg_k8s

    # SSM + IAM role flow
    iam_ec2 >> Edge(style="dotted", label="assume") >> sg_k8s
    iam_ec2 >> Edge(style="dotted") >> sg_pm_ec2
    sg_k8s >> Edge(style="dashed", label="put/get join cmd") >> ssm

    # Autosign attached to master
    autosign >> Edge(style="dotted", label="restricts cert signing") >> sg_pm_ec2
