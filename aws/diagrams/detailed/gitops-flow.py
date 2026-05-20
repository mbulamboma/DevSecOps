"""
GitOps flow — git push to GitHub triggers Puppet catalog update on slaves.

  1. Admin pushes commits to control-repo (branch: production)
  2. r10k cron on Puppet Master ASG pulls latest every minute
  3. Master compiles catalogs from production environment
  4. Foreman (public) provides ENC data and node classification
  5. Puppet agents on k8s nodes run every 5 minutes -> pick up new catalog
  6. PuppetDB ASG stores facts/reports
"""

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EC2, EC2AutoScaling as AutoScaling
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
    admin = Users("Admin")

    with Cluster("Step 1 — Source of truth"):
        gh = Github("control-repo\nproduction branch")

    with Cluster("Step 2 — Foreman (Public ALB)"):
        foreman_alb = ELB("Foreman ALB\nHTTPS :443\n(internet-facing)")
        foreman_asg = AutoScaling("Foreman ASG\nmin 1 / max 2")

    with Cluster("Step 3 — Pull & Compile (Internal)"):
        master_alb = ELB("Puppet Master ALB\n:8140 internal")
        master_asg = AutoScaling("Puppet Master ASG\nmin 1 / max 2\nr10k deploy -p (60s)")

    with Cluster("Step 4 — Apply (agent run every 5m)"):
        cp = EC2("k8s-control-plane\npuppet-agent")
        wk = EC2("k8s-worker-node\npuppet-agent")

    with Cluster("Step 5 — Reports (Internal)"):
        pdb_alb = ELB("PuppetDB ALB\n:8081 internal")
        pdb_asg = AutoScaling("PuppetDB ASG\nmin 1 / max 2")
        rds = RDSPostgresqlInstance("RDS Postgres\nforeman + puppetdb")

    # Developer pushes code
    dev >> Edge(label="git push") >> gh
    
    # r10k pulls from GitHub
    gh >> Edge(label="HTTPS clone\n(every 60s)", color="darkgreen") >> master_asg
    
    # Admin manages nodes via Foreman
    admin >> Edge(label="HTTPS") >> foreman_alb >> foreman_asg
    
    # Foreman provides ENC to Puppet Master
    foreman_asg >> Edge(label="ENC /nodes\n:8140", style="dashed") >> master_alb
    
    # Puppet Master serves catalogs
    master_alb >> master_asg
    master_asg >> Edge(label="catalog :8140") >> cp
    master_asg >> Edge(label="catalog :8140") >> wk

    # Agents send facts/reports to PuppetDB
    cp >> Edge(label="facts/reports") >> pdb_alb
    wk >> Edge(label="facts/reports") >> pdb_alb
    pdb_alb >> pdb_asg
    
    # PuppetDB and Foreman share RDS
    pdb_asg >> Edge(label=":5432") >> rds
    foreman_asg >> Edge(label=":5432", style="dashed") >> rds
