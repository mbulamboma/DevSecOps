"""
Overview — Logical data flows between Puppet components.

Shows the catalog compilation / fact storage / reporting flows.
"""

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EC2AutoScaling as AutoScaling
from diagrams.aws.database import RDSPostgresqlInstance
from diagrams.aws.network import ELB
from diagrams.onprem.client import Users


graph_attr = {"fontsize": "16", "labelloc": "t", "pad": "0.4"}

with Diagram(
    "Puppet stack — Data flows",
    filename="data-flow-overview",
    show=False,
    direction="LR",
    graph_attr=graph_attr,
):
    admin = Users("Admin UI")
    agent = Users("Puppet Agent\n(node)")

    with Cluster("Foreman"):
        fm_alb = ELB("Foreman ALB :443")
        fm_asg = AutoScaling("Foreman ASG")

    with Cluster("Puppet Master"):
        pm_alb = ELB("Master ALB :8140")
        pm_asg = AutoScaling("Master ASG")

    with Cluster("PuppetDB"):
        pdb_alb = ELB("PuppetDB ALB :8080")
        pdb_asg = AutoScaling("PuppetDB ASG")

    rds = RDSPostgresqlInstance("PostgreSQL\nforeman + puppetdb")

    admin >> Edge(label="manage hosts / classes") >> fm_alb >> fm_asg
    fm_asg >> Edge(label="ENC / nodes API") >> pm_alb

    agent >> Edge(label="request catalog") >> pm_alb >> pm_asg
    pm_asg >> Edge(label="store facts / catalog / reports") >> pdb_alb >> pdb_asg

    fm_asg >> Edge(label="foreman DB") >> rds
    pdb_asg >> Edge(label="puppetdb DB") >> rds
    fm_asg >> Edge(style="dashed", label="query facts") >> pdb_alb
