"""
Overview — Network topology.

Shows VPC, public/private subnets per AZ, IGW, ALB placement.
"""

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EC2AutoScaling as AutoScaling
from diagrams.aws.database import RDSPostgresqlInstance
from diagrams.aws.network import ELB, InternetGateway, Route53, VPC
from diagrams.onprem.client import Users


graph_attr = {"fontsize": "16", "labelloc": "t", "pad": "0.4", "splines": "spline"}

with Diagram(
    "Puppet stack — Network topology",
    filename="network-overview",
    show=False,
    direction="TB",
    graph_attr=graph_attr,
):
    user = Users("Internet")
    dns = Route53("foreman.emlinkapp.com")

    with Cluster("VPC vpc-0aedda8091caa685a  (us-east-2)"):
        VPC("VPC")
        igw = InternetGateway("Internet Gateway")

        with Cluster("Availability Zone us-east-2a"):
            with Cluster("Public subnet  04c160f3b2b116f67"):
                pub_a_fm = AutoScaling("Foreman EC2 (AZ-a)")
                pub_a_pm = AutoScaling("PuppetMaster EC2 (AZ-a)")
                pub_a_pdb = AutoScaling("PuppetDB EC2 (AZ-a)")
            with Cluster("Private subnet  03597fa031fba14ec"):
                rds_a = RDSPostgresqlInstance("RDS primary")

        with Cluster("Availability Zone us-east-2b"):
            with Cluster("Public subnet  0561803e5777a8641"):
                pub_b_fm = AutoScaling("Foreman EC2 (AZ-b, scale-out)")
                pub_b_pm = AutoScaling("PuppetMaster EC2 (AZ-b, scale-out)")
                pub_b_pdb = AutoScaling("PuppetDB EC2 (AZ-b, scale-out)")
            with Cluster("Private subnet  0490d6139a724c5e8"):
                pass  # multi-az candidate

        with Cluster("Load balancers"):
            alb_fm = ELB("Foreman ALB  (public, 2 AZ public subnets)")
            alb_pm = ELB("Puppet Master ALB  (internal, 2 AZ private subnets)")
            alb_pdb = ELB("PuppetDB ALB  (internal, 2 AZ private subnets)")

    user >> Edge(label="HTTPS") >> dns >> alb_fm
    igw >> Edge(style="dotted") >> alb_fm

    alb_fm >> [pub_a_fm, pub_b_fm]
    alb_pm >> [pub_a_pm, pub_b_pm]
    alb_pdb >> [pub_a_pdb, pub_b_pdb]

    [pub_a_fm, pub_b_fm, pub_a_pdb, pub_b_pdb] >> Edge(label="pg :5432") >> rds_a
