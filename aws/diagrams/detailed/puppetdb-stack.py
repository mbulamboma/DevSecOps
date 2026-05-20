"""
Detailed â€” PuppetDB stack only.

Internal ALB (HTTP :8080) -> PuppetDB ASG -> RDS (puppetdb DB).
Only reachable from inside 10.0.0.0/16.
"""

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EC2, EC2AutoScaling as AutoScaling
from diagrams.aws.compute import EC2 as LaunchTemplate
from diagrams.aws.database import RDSPostgresqlInstance
from diagrams.aws.network import ELB
from diagrams.aws.security import IAMPermissions
from diagrams.onprem.compute import Server


graph_attr = {"fontsize": "15", "labelloc": "t", "pad": "0.5"}

with Diagram(
    "PuppetDB stack â€” Detailed",
    filename="puppetdb-stack",
    show=False,
    direction="TB",
    graph_attr=graph_attr,
):
    callers = Server("Puppet Master EC2s\n(in VPC)")

    with Cluster("VPC us-east-2"):
        with Cluster("Internal ALB (private subnets, 2 AZ)"):
            alb = ELB(
                "ALB puppetdb (internal)\n:8080 HTTP\n"
                "TG :8080 HTTP Â· HC /pdb/meta/v1/version\n"
                "Stickiness lb_cookie 1d"
            )

        with Cluster("Compute (public subnets, 2 AZ)"):
            lt = LaunchTemplate("LT puppetdb\nUbuntu 22.04 Â· t3.medium\nIMDSv2 Â· gp3 encrypted")
            asg = AutoScaling("ASG puppetdb\nmin 1 / max 2 / desired 1\nRolling refresh")
            ec2 = [EC2("PuppetDB EC2 a"), EC2("PuppetDB EC2 b (scale-out)")]

        with Cluster("Private subnets"):
            rds = RDSPostgresqlInstance(
                "RDS Postgres 16\npuppetdb-pg Â· db.t3.micro\n"
                "DB: puppetdb Â· pg_trgm"
            )

        sg_alb = IAMPermissions("SG ALB\nin: 8080 â† 10.0.0.0/16")
        sg_ec2 = IAMPermissions("SG EC2\nin: 22 Â· in: 8080 â† SG ALB")
        sg_rds = IAMPermissions("SG RDS\nin: 5432 â† SG EC2")

    callers >> Edge(label=":8080") >> alb >> Edge(label=":8080") >> asg
    lt >> Edge(style="dashed", label="provisions") >> asg
    asg >> ec2
    ec2[0] >> Edge(label="pg :5432") >> rds

    sg_alb >> Edge(style="dotted") >> alb
    sg_ec2 >> Edge(style="dotted") >> ec2[0]
    sg_rds >> Edge(style="dotted") >> rds

