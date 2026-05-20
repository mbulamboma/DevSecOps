"""
Detailed â€” Puppet Master stack only.

Internal ALB (HTTP :8140) -> Master ASG -> PuppetDB internal ALB.
"""

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EC2, EC2AutoScaling as AutoScaling
from diagrams.aws.compute import EC2 as LaunchTemplate
from diagrams.aws.network import ELB
from diagrams.aws.security import IAMPermissions
from diagrams.onprem.client import Users
from diagrams.onprem.compute import Server


graph_attr = {"fontsize": "15", "labelloc": "t", "pad": "0.5"}

with Diagram(
    "Puppet Master stack â€” Detailed",
    filename="puppet-masters-stack",
    show=False,
    direction="TB",
    graph_attr=graph_attr,
):
    agents = Users("Puppet Agents\n(managed nodes in VPC)")
    foreman = Server("Foreman EC2s")
    puppetdb = Server("PuppetDB internal ALB\n:8080")

    with Cluster("VPC us-east-2"):
        with Cluster("Internal ALB (private subnets, 2 AZ)"):
            alb = ELB(
                "ALB puppet-master (internal)\n:8140 HTTP\n"
                "TG :8140 HTTP Â· HC /status/v1/services\n"
                "Stickiness lb_cookie 1d"
            )

        with Cluster("Compute (public subnets, 2 AZ)"):
            lt = LaunchTemplate("LT puppet-master\nUbuntu 22.04 Â· t3.medium")
            asg = AutoScaling("ASG puppet-master\nmin 1 / max 2 / desired 1")
            ec2 = [EC2("Master EC2 a"), EC2("Master EC2 b (scale-out)")]

        sg_alb = IAMPermissions("SG ALB\nin: 8140 â† 10.0.0.0/16")
        sg_ec2 = IAMPermissions("SG EC2\nin: 22 Â· in: 8140 â† SG ALB")

    agents >> Edge(label=":8140") >> alb
    foreman >> Edge(label=":8140 ENC") >> alb
    alb >> Edge(label=":8140") >> asg
    lt >> Edge(style="dashed", label="provisions") >> asg
    asg >> ec2
    ec2[0] >> Edge(label=":8080 facts/reports") >> puppetdb

    sg_alb >> Edge(style="dotted") >> alb
    sg_ec2 >> Edge(style="dotted") >> ec2[0]

