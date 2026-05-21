"""
GitOps flow — AWS Architecture with Puppet Server infrastructure.
"""

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EC2, EC2AutoScaling
from diagrams.aws.database import RDS
from diagrams.aws.network import ALB, Route53, NATGateway, InternetGateway
from diagrams.aws.security import ACM
from diagrams.onprem.vcs import Github
from diagrams.onprem.client import User

graph_attr = {
    "fontsize": "10",
    "bgcolor": "white",
    "pad": "0.2",
    "splines": "spline",
    "nodesep": "0.3",
    "ranksep": "0.4",
    "compound": "true",
}

node_attr = {"fontsize": "8", "width": "1.2", "height": "1.2"}
edge_attr = {"fontsize": "7"}

with Diagram(
    "GitOps Flow - AWS",
    filename="gitops-flow",
    show=False,
    direction="LR",
    graph_attr=graph_attr,
    node_attr=node_attr,
    edge_attr=edge_attr,
):
    # External users
    dev = User("Dev")
    admin = User("Admin")
    github = Github("GitHub")

    with Cluster("AWS VPC"):
        dns = Route53("R53")
        acm = ACM("ACM")
        igw = InternetGateway("IGW")
        nat = NATGateway("NAT")
        
        with Cluster("Public"):
            foreman_alb = ALB("Foreman\nALB:443")
            k8s_alb = ALB("K8s Apps\nALB:443")
        
        with Cluster("Private - Puppet"):
            puppet_alb = ALB("Puppet\nALB:8140")
            pdb_alb = ALB("PuppetDB\nALB:8081")
            
            foreman = EC2("Foreman")
            puppet = EC2("Puppet\nServer")
            puppetdb = EC2("PuppetDB")
        
        with Cluster("Private - K8s"):
            k8s_cp = EC2("CP")
            k8s_wk = EC2("Worker")
            # Force horizontal layout
            k8s_cp - Edge(style="invis") - k8s_wk
        
        rds = RDS("RDS\nPostgres")

    # Flows
    dev >> Edge(label="push", color="green") >> github
    github >> Edge(label="r10k", color="green") >> nat >> puppet
    
    admin >> dns >> igw >> foreman_alb >> foreman
    acm - Edge(style="dashed") - foreman_alb
    
    foreman >> Edge(label="ENC", style="dashed") >> puppet_alb >> puppet
    
    [k8s_cp, k8s_wk] >> Edge(label="catalog", color="blue") >> puppet_alb
    
    puppet >> pdb_alb >> puppetdb >> rds
    foreman >> Edge(style="dashed") >> rds
    
    # K8s Apps ALB exposes pods
    igw >> k8s_alb >> Edge(label="pods", color="darkblue") >> k8s_wk
    acm - Edge(style="dashed") - k8s_alb
