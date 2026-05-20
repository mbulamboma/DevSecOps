"""
Detailed â€” Foreman stack only.

Public ALB (HTTPS :443) -> Foreman ASG -> RDS (foreman DB).
"""

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EC2, EC2AutoScaling as AutoScaling
from diagrams.aws.compute import EC2 as LaunchTemplate
from diagrams.aws.database import RDSPostgresqlInstance
from diagrams.aws.network import ELB, InternetGateway, Route53
from diagrams.aws.security import ACM, IAMPermissions
from diagrams.onprem.client import Users


graph_attr = {"fontsize": "15", "labelloc": "t", "pad": "0.5"}

with Diagram(
    "Foreman stack â€” Detailed",
    filename="foreman-stack",
    show=False,
    direction="TB",
    graph_attr=graph_attr,
):
    user = Users("Admin / Browser")
    dns = Route53("foreman.emlinkapp.com\nA ALIAS â†’ ALB")
    cert = ACM("ACM cert")

    with Cluster("VPC us-east-2"):
        igw = InternetGateway("IGW")

        with Cluster("Public subnets (2 AZ)"):
            alb = ELB(
                "ALB foreman (public)\n:80 redirect â†’ :443\n:443 HTTPS (ACM)\n"
                "TG :443 HTTPS Â· HC /users/login\nStickiness lb_cookie 1d"
            )
            lt = LaunchTemplate("LT foreman\nUbuntu 22.04 Â· t3.medium\nIMDSv2 Â· gp3 encrypted")
            asg = AutoScaling("ASG foreman\nmin 1 / max 2 / desired 1\nRolling refresh")
            ec2 = [EC2("Foreman EC2 a"), EC2("Foreman EC2 b (scale-out)")]

        with Cluster("Private subnets"):
            rds = RDSPostgresqlInstance("RDS Postgres 16\n(shared, foreman DB)")

        sg_alb = IAMPermissions("SG ALB\nin: 80,443 â† 0.0.0.0/0")
        sg_ec2 = IAMPermissions("SG EC2\nin: 22 â† 0.0.0.0/0\nin: 443 â† SG ALB")
        sg_rds = IAMPermissions("SG RDS\nin: 5432 â† SG EC2 (cross-stack rule)")

    user >> Edge(label="HTTPS") >> dns >> alb
    cert >> Edge(style="dashed") >> alb
    igw >> Edge(style="dotted") >> alb
    alb >> Edge(label=":443") >> asg
    lt >> Edge(style="dashed", label="provisions") >> asg
    asg >> ec2
    ec2[0] >> Edge(label="pg :5432") >> rds

    sg_alb >> Edge(style="dotted") >> alb
    sg_ec2 >> Edge(style="dotted") >> ec2[0]
    sg_rds >> Edge(style="dotted") >> rds

