"""
Kubernetes slave nodes (1 control plane + 1 worker) - self-bootstrapped via user-data.

  - CP runs kubeadm init in user-data, applies Flannel CNI, deploys nginx test app,
    and publishes the kubeadm join command to SSM Parameter Store.
  - Worker polls SSM for the join command and runs kubeadm join.
  - Test app (nginx Deployment, 2 replicas) is exposed via NodePort 30080
    behind a public ALB so it is reachable from the internet.
"""

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EC2
from diagrams.aws.network import ELB
from diagrams.aws.management import SSM
from diagrams.k8s.infra import Master as K8sMaster, Node as K8sNode
from diagrams.k8s.compute import Deployment, Pod
from diagrams.k8s.network import Service
from diagrams.onprem.client import Users

graph_attr = {"fontsize": "16", "labelloc": "t", "pad": "0.4", "splines": "spline"}

with Diagram(
    "Kubernetes self-bootstrapping stack + public test app",
    filename="k8s-stack",
    show=False,
    direction="LR",
    graph_attr=graph_attr,
):
    internet = Users("Internet user\nGET /")

    with Cluster("AWS VPC vpc-0aedda8091caa685a (us-east-2)"):

        with Cluster("Public subnets"):
            alb_web = ELB("devsecops-web-alb\nHTTP :80 -> :30080\n(internet-facing)")

        ssm = SSM("SSM Parameter Store\n/k8s/join-command\n(SecureString)")

        with Cluster("Private subnets"):
            with Cluster("Control plane (us-east-2a)"):
                k8s_cp = EC2("k8s-control-plane\nt3.medium")
                k8s_api = K8sMaster("kube-apiserver :6443\netcd, Flannel CNI")
            with Cluster("Worker (us-east-2b)"):
                k8s_wk = EC2("k8s-worker-node\nt3.medium\nNodePort 30080")
                k8s_kubelet = K8sNode("kubelet + containerd")

            with Cluster("Test app on cluster"):
                dep = Deployment("Deployment web\nnginx:1.27-alpine x2")
                pod1 = Pod("pod web-*")
                pod2 = Pod("pod web-*")
                svc = Service("Service web-svc\nNodePort 30080")

    # Self-bootstrap flow
    k8s_cp >> Edge(label="put-parameter\n(join cmd)", style="dashed") >> ssm
    ssm >> Edge(label="get-parameter\n(poll)", style="dashed") >> k8s_wk
    k8s_wk >> Edge(label="kubeadm join :6443") >> k8s_cp

    # App data path
    internet >> Edge(label="HTTP :80") >> alb_web
    alb_web >> Edge(label=":30080") >> k8s_wk
    k8s_wk >> Edge(style="dotted") >> svc
    svc >> Edge(style="dotted") >> dep
    dep - Edge(style="invis") - pod1
    dep - Edge(style="invis") - pod2

    k8s_cp - Edge(style="invis") - k8s_api
    k8s_wk - Edge(style="invis") - k8s_kubelet
