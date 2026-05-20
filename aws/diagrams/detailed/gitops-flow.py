"""
GitOps flow — git push to GitHub triggers Puppet catalog update on slaves.

  1. Admin pushes commits to control-repo (branch: production)
  2. r10k cron on Puppet Master pulls latest every minute
  3. Master compiles catalogs from production environment
  4. Puppet agents on k8s nodes run every 5 minutes -> pick up new catalog
  5. PuppetDB stores facts/reports
"""

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EC2
from diagrams.aws.database import RDSPostgresqlInstance
from diagrams.aws.network import ELB
from diagrams.onprem.vcs import Github
from diagrams.onprem.client import Users

graph_attr = {"fontsize": "16", "labelloc": "t", "pad": "0.5", "splines": "spline"}

with Diagram(
    "GitOps end-to-end flow (GitHub -> r10k -> Puppet agents)",
    filename="gitops-flow",
    show=False,
    direction="LR",
    graph_attr=graph_attr,
):
    dev = Users("Developer")

    with Cluster("Step 1 — Source of truth"):
        gh = Github("control-repo\nproduction branch")

    with Cluster("Step 2 — Pull (every 60s)"):
        master = EC2("Puppet Master\nr10k deploy -p")

    with Cluster("Step 3 — Compile"):
        master_compile = EC2("puppetserver :8140\nproduction env")

    with Cluster("Step 4 — Apply (agent run every 5m)"):
        cp = EC2("k8s-control-plane")
        wk = EC2("k8s-worker-node")

    with Cluster("Step 5 — Reports"):
        pdb_alb = ELB("PuppetDB ALB :8080")
        pdb = EC2("PuppetDB")
        rds = RDSPostgresqlInstance("RDS Postgres\npuppetdb db")

    dev >> Edge(label="git push") >> gh
    gh >> Edge(label="HTTPS clone") >> master
    master >> Edge(style="dashed") >> master_compile

    master_compile >> Edge(label="catalog :8140") >> cp
    master_compile >> Edge(label="catalog :8140") >> wk

    cp >> Edge(label="facts/reports") >> pdb_alb
    wk >> Edge(label="facts/reports") >> pdb_alb
    pdb_alb >> pdb >> Edge(label=":5432") >> rds
