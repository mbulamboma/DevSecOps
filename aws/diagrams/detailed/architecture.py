"""
Detailed architecture - the complete DevSecOps stack on AWS (live state).

Includes Foreman + Puppet Master + PuppetDB + Kubernetes (1 CP + 1 worker)
+ public app ALB, GitHub control-repo -> r10k flow, EICE for SSH-less access,
all 4 ALBs, all 3 ASGs, RDS, IGW, NAT GW, ACM, DNS.
"""

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EC2, EC2AutoScaling as AutoScaling
from diagrams.aws.database import RDSPostgresqlInstance
from diagrams.aws.management import SystemsManager as SSM
from diagrams.aws.network import ELB, InternetGateway, NATGateway, Route53, VPC
from diagrams.aws.security import ACM, IAMPermissions
from diagrams.k8s.compute import Deployment, Pod
from diagrams.k8s.network import Service
from diagrams.onprem.client import Users
from diagrams.onprem.vcs import Github


graph_attr = {
    "fontsize": "14",
    "labelloc": "t",
    "pad": "0.5",
    "splines": "spline",
    "rankdir": "TB",
}

with Diagram(
    "DevSecOps stack on AWS - Detailed architecture (live)",
    filename="architecture",
    show=False,
    direction="TB",
    graph_attr=graph_attr,
):
    admin = Users("Admin / Browser")
    dev = Users("Developer\ngit push")
    web_user = Users("Internet user\nGET /")
    gh = Github("github.com/mbulamboma\ndevsecops-puppet-control\nproduction branch")

    with Cluster("Route 53 - emlinkapp.com"):
        dns = Route53("foreman.emlinkapp.com\nALIAS -> Foreman ALB")

    cert = ACM("ACM cert\n*.emlinkapp.com")

    with Cluster("VPC vpc-0aedda8091caa685a  (us-east-2)"):
        VPC("VPC 10.0.0.0/16")
        igw = InternetGateway("Internet Gateway")
        nat = NATGateway("NAT GW (us-east-2a)\negress for private subnets")
        eice = IAMPermissions("EICE\neice-0d901a8144ab2e126\n(SSH tunnel, no public SSH)")

        with Cluster("Foreman tier - public ALB (2 AZ public subnets)"):
            alb_fm = ELB(
                "foreman-alb (internet-facing)\n"
                ":80 -> redirect :443\n"
                ":443 HTTPS (ACM)\nHC /users/login"
            )
            asg_fm = AutoScaling("Foreman ASG\nmin 1 / max 2 / desired 1")
            ec2_fm = EC2("i-01e56b58d22c6ca56\n52.14.45.101 (us-east-2b)")

        with Cluster("Puppet Master tier - internal ALB"):
            alb_pm = ELB(
                "internal-puppet-master-alb\n:8140 HTTP\nHC /status/v1/services"
            )
            asg_pm = AutoScaling("Master ASG\nmin 1 / max 2 / desired 1")
            ec2_pm = EC2("i-0fb8d4478ff5035e9\n18.224.61.140 (us-east-2a)\nr10k cron 1m")

        with Cluster("PuppetDB tier - internal ALB"):
            alb_pdb = ELB(
                "internal-puppetdb-alb\n:8080 HTTP\nHC /pdb/meta/v1/version"
            )
            asg_pdb = AutoScaling("PuppetDB ASG\nmin 1 / max 2 / desired 1")
            ec2_pdb = EC2("i-0cb91b27247bddd42\n18.219.216.204 (us-east-2b)")

        with Cluster("Kubernetes tier - private subnets"):
            alb_web = ELB(
                "devsecops-web-alb (internet-facing)\nHTTP :80 -> :30080"
            )
            k8s_cp = EC2("k8s-control-plane\ni-0aab823665dd93c01\npriv 10.0.131.67 (us-east-2a)")
            k8s_wk = EC2("k8s-worker-node\ni-04aef694afe170455\npriv 10.0.157.171 (us-east-2b)\nNodePort 30080")
            svc = Service("Service web-svc\nNodePort 30080")
            dep = Deployment("Deployment web\nnginx:1.27-alpine x2")
            pod = Pod("web pods")

        ssm = SSM("SSM Parameter Store\n/k8s/join-command\n(SecureString)")

        with Cluster("Data tier - private subnets"):
            rds = RDSPostgresqlInstance(
                "RDS Postgres 16\ndb.t3.micro\nDBs: foreman, puppetdb"
            )

    # ----- North/south traffic -----
    admin >> Edge(label="HTTPS") >> dns >> alb_fm
    cert >> Edge(style="dashed", label="TLS") >> alb_fm
    igw >> Edge(style="dotted") >> alb_fm
    igw >> Edge(style="dotted") >> alb_web
    web_user >> Edge(label="HTTP :80") >> alb_web

    alb_fm >> Edge(label=":443") >> asg_fm >> ec2_fm

    # ----- GitOps -----
    dev >> Edge(label="git push") >> gh
    gh >> Edge(label="r10k pull (60s)", color="darkgreen") >> ec2_pm

    # ----- Puppet control plane -----
    ec2_fm >> Edge(label=":8140 ENC/nodes") >> alb_pm
    alb_pm >> Edge(label=":8140") >> asg_pm >> ec2_pm
    ec2_pm >> Edge(label=":8080 facts/reports") >> alb_pdb
    alb_pdb >> Edge(label=":8080") >> asg_pdb >> ec2_pdb

    # ----- k8s agent flow -----
    k8s_cp >> Edge(label="puppet-agent :8140") >> alb_pm
    k8s_wk >> Edge(label="puppet-agent :8140") >> alb_pm

    # ----- k8s bootstrap -----
    k8s_cp >> Edge(label="put join cmd", style="dashed") >> ssm
    ssm >> Edge(label="get join cmd", style="dashed") >> k8s_wk
    k8s_wk >> Edge(label="kubeadm join :6443") >> k8s_cp

    # ----- App data path -----
    alb_web >> Edge(label=":30080") >> k8s_wk
    k8s_wk >> Edge(style="dotted") >> svc >> Edge(style="dotted") >> dep >> Edge(style="dotted") >> pod

    # ----- Egress + EICE -----
    [k8s_cp, k8s_wk] >> Edge(style="dotted", label="egress") >> nat
    eice >> Edge(style="dashed", label="SSH :22 (IAM auth)") >> ec2_fm
    eice >> Edge(style="dashed") >> ec2_pm
    eice >> Edge(style="dashed") >> ec2_pdb
    eice >> Edge(style="dashed") >> k8s_cp
    eice >> Edge(style="dashed") >> k8s_wk

    # ----- DB -----
    ec2_fm >> Edge(label="pg :5432") >> rds
    ec2_pdb >> Edge(label="pg :5432") >> rds
