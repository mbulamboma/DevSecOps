"""
High-level overview — full Puppet stack on AWS including K8s managed nodes.

  User -> Route53/ACM -> Foreman public ALB -> Foreman ASG
  Foreman / Agents -> Puppet Master internal ALB -> Master ASG
  Master ASG -> PuppetDB internal ALB -> PuppetDB ASG -> RDS PostgreSQL
  K8s control-plane + worker (private subnets) -> Master ALB
  GitHub control-repo -> r10k on Puppet Master (single source of truth)
"""

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EC2, EC2AutoScaling as AutoScaling
from diagrams.aws.database import RDSPostgresqlInstance
from diagrams.aws.network import ELB, NATGateway, Route53
from diagrams.aws.security import ACM
from diagrams.k8s.infra import Master as K8sMaster, Node as K8sNode
from diagrams.onprem.client import Users
from diagrams.onprem.vcs import Github


graph_attr = {"fontsize": "18", "labelloc": "t", "pad": "0.4", "splines": "spline"}

with Diagram(
    "Puppet + Kubernetes stack on AWS - Overview",
    filename="overview",
    show=False,
    direction="LR",
    graph_attr=graph_attr,
):
    admin = Users("Admin / Browser")
    dev = Users("Developer\ngit push")
    gh = Github("github.com\ncontrol-repo\nproduction branch")

    dns = Route53("foreman.emlinkapp.com")
    cert = ACM("ACM cert\n*.emlinkapp.com")

    with Cluster("AWS VPC (us-east-2)"):
        with Cluster("Public tier"):
            alb_fm = ELB("Foreman ALB\nHTTPS :443")
            asg_fm = AutoScaling("Foreman ASG\nmin 1 / max 2")

        with Cluster("Internal tier - Puppet control plane"):
            alb_pm = ELB("Puppet Master ALB\n:8140 internal")
            asg_pm = AutoScaling("Puppet Master ASG")

            alb_pdb = ELB("PuppetDB ALB\n:8081 https internal")
            asg_pdb = AutoScaling("PuppetDB ASG")

        with Cluster("Private subnets - Kubernetes managed nodes"):
            nat = NATGateway("NAT GW\negress only")
            k8s_cp = EC2("k8s-control-plane\npuppet-agent")
            k8s_api = K8sMaster("kube-apiserver :6443\netcd + flannel CNI")
            k8s_wk = EC2("k8s-worker-node\npuppet-agent")
            k8s_kubelet = K8sNode("kubelet\nNodePorts 30000-32767")

        with Cluster("Data tier (private subnets)"):
            rds = RDSPostgresqlInstance("RDS PostgreSQL 16\nforeman + puppetdb")

    admin >> Edge(label="HTTPS") >> dns >> alb_fm
    cert >> Edge(style="dashed", label="TLS") >> alb_fm
    alb_fm >> Edge(label=":443") >> asg_fm

    dev >> Edge(label="git push") >> gh
    gh >> Edge(label="r10k pull / 60s", color="darkgreen") >> asg_pm
    gh >> Edge(style="dashed", color="darkgreen", label="ENC sync") >> asg_fm

    asg_fm >> Edge(label=":8140 ENC/nodes") >> alb_pm
    alb_pm >> Edge(label=":8140") >> asg_pm
    asg_pm >> Edge(label=":8081 facts/reports") >> alb_pdb
    alb_pdb >> Edge(label=":8081") >> asg_pdb

    k8s_cp >> Edge(label="agent :8140\npuppet-master.internal") >> alb_pm
    k8s_wk >> Edge(label="agent :8140\npuppet-master.internal") >> alb_pm

    k8s_wk >> Edge(label="kubeadm join :6443") >> k8s_cp
    k8s_cp - Edge(style="invis") - k8s_api
    k8s_wk - Edge(style="invis") - k8s_kubelet

    [k8s_cp, k8s_wk] >> Edge(style="dotted", label="egress\nimage pulls") >> nat

    asg_fm >> Edge(label="pg :5432") >> rds
    asg_pdb >> Edge(label="pg :5432") >> rds
