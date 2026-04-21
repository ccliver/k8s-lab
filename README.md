# k8s-lab

A Kubernetes lab on AWS EKS for CKA studying and exploring tools in the Kubernetes ecosystem. Infrastructure is managed with Terraform and a [Taskfile](https://taskfile.dev) runner. GitOps is handled by ArgoCD.

## Architecture

```
┌──────────┐                ┌────────────────────────────────────────────────────────────────┐
│  Browser │── HTTP:80 ────▶│                               AWS                              │
└──────────┘                │                                                                │
                            │   ┌────────────────────────────────────────────────────────┐   │
                            │   │       ALB  (internet-facing · IngressGroup "lab")      │   │
                            │   └──────────────────┬──────────────────────┬──────────────┘   │
                            │                      │ /argocd              │ /grafana         │
┌──────────┐                │   ┌──────────────────▼──────────────────────▼──────────────┐   │
│ Git repo │                │   │                 EKS Cluster (k8s-lab)                  │   │
│  (apps/) │◀── ArgoCD ─────┤   │      K8s 1.34 · t4g.medium SPOT · ARM/Graviton · 3–6   │   │
└──────────┘                │   │                                                        │   │
                            │   │  ┌──────────────────────┐  ┌──────────────────────┐    │   │
                            │   │  │   ns: kube-system    │  │      ns: argocd      │    │   │
                            │   │  │   · AWS LBC          │  │  · ArgoCD            │    │   │
                            │   │  │   · Cluster Auto-    │  │    (app-of-apps)     │    │   │
                            │   │  │     scaler           │  └──────────────────────┘    │   │
                            │   │  └──────────────────────┘                              │   │
                            │   │  ┌──────────────────────┐  ┌─────────────────────┐     │   │
                            │   │  │   ns: monitoring     │  │   ns: http-canary   │     │   │
                            │   │  │   · Prometheus       │  │  · HTTP Canary      │     │   │
                            │   │  │   · Grafana          │  │    (custom metrics) │     │   │
                            │   │  └──────────────────────┘  └─────────────────────┘     │   │
                            │   │  ┌──────────────────────┐  ┌─────────────────────┐     │   │
                            │   │  │   ns: cnpg-system    │  │   ns: postgresql    │     │   │
                            │   │  │   · CloudNativePG    │  │  · PostgreSQL       │     │   │
                            │   │  │     Operator         │  │    Cluster (CNPG)   │     │   │
                            │   │  └──────────────────────┘  └─────────────────────┘     │   │
                            │   │  ┌─────────────────────────────────────────────────┐   │   │
                            │   │  │   ns: k8s-lab-status                            │   │   │
                            │   │  │   · Status app (Secrets Manager CSI + EFS demo) │   │   │
                            │   │  └─────────────────────────────────────────────────┘   │   │
                            │   └────────────────────────────────────────────────────────┘   │
                            │                                                                │
                            │   IAM (IRSA: LBC · Cluster Autoscaler · EBS/EFS CSI)           │
                            │   S3 (TF state)  ·  EFS  ·  Secrets Manager (CSI driver)       │
                            └────────────────────────────────────────────────────────────────┘
```

ArgoCD and Grafana share a single internet-facing ALB via an IngressGroup (`lab`), path-routed at `/argocd` and `/grafana`. ArgoCD watches the `apps/` directory in this repo and uses the [app-of-apps](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/) pattern to sync all managed applications.

## Prerequisites

| Tool | Purpose |
|------|---------|
| [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.0 | Infrastructure provisioning |
| [task](https://taskfile.dev/installation/) | Task runner |
| [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) | AWS operations (profile: `lab`) |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | Cluster interaction |
| [helm](https://helm.sh/docs/intro/install/) | Chart installs |
| [envsubst](https://www.gnu.org/software/gettext/) | Manifest templating |

An AWS profile named `lab` must be configured in `~/.aws/credentials` / `~/.aws/config`.

## Quick Start

```bash
# 1. Set CIDRs allowed to reach the EKS API and ALB (your public IP)
# Create terraform/terraform.tfvars:
#   endpoint_public_access_cidrs = ["x.x.x.x/32"]
#   alb_allowed_cidrs            = ["x.x.x.x/32"]

# 2. Deploy everything (Terraform + LBC + ArgoCD + monitoring)
task deploy

# 3. Get the ALB URL
task alb-dns
# ArgoCD → http://<alb-dns>/argocd
# Grafana → http://<alb-dns>/grafana

# 4. Retrieve default passwords
task argocd-password
task grafana-password
```

## Available Tasks

```
task deploy                  Deploy lab (Terraform + Helm + ingress)
task destroy                 Tear down lab (order-safe multi-stage)
task tf-plan                 Show Terraform plan
task kubeconfig              Add/update cluster in ~/.kube/config
task alb-dns                 Print the ALB DNS name
task argocd-pf               Port-forward ArgoCD UI → http://127.0.0.1:8080
task k8s-lab-status-pf       Port-forward k8s-lab-status app
task argocd-password         Retrieve ArgoCD admin password
task grafana-password        Retrieve Grafana admin password
task publish-http-canary     Build and push http-canary image to Docker Hub (TAG=<tag>, default: latest)
```

## Repository Layout

```
.
├── Taskfile.yml              # All day-to-day operations
├── terraform/                # AWS infrastructure (EKS, VPC, IAM, ALB SG)
│   ├── main.tf               # ccliver/k8s-lab/aws module call
│   ├── variables.tf          # endpoint_public_access_cidrs, alb_allowed_cidrs
│   ├── output.tf             # aws_lbc_role_arn, vpc_id, alb_security_group_id, cluster_autoscaler_role_arn
│   ├── backend.tf            # S3 remote state (us-east-1)
│   └── versions.tf           # Terraform >= 1.0, AWS ~> 6
├── manifests/                # Raw K8s manifests (ingresses/StorageClasses applied by Taskfile; others managed by ArgoCD)
│   ├── argocd-ingress.yaml              # ArgoCD ALB ingress (envsubst for SG ID)
│   ├── grafana-ingress.yaml             # Grafana ALB ingress (envsubst for SG ID)
│   ├── http-canary.yaml                 # http-canary Deployment/Service/ServiceMonitor (managed by ArgoCD)
│   ├── k8s-lab-status.yaml              # k8s-lab-status app (managed by ArgoCD)
│   ├── gp3-storage-class.yaml           # gp3 StorageClass (default, replaces gp2)
│   ├── io2-storage-class.yaml           # io2 StorageClass for high-performance workloads
│   ├── efs-storage-class.yaml           # EFS StorageClass
│   ├── ebs-volume-snapshot-class.yaml   # EBS VolumeSnapshotClass
│   ├── fake-api-key-secret-provider-class.yaml  # SecretProviderClass for Secrets Manager demo
│   ├── nginx-efs.yaml                   # Nginx deployment on EFS (demo)
│   └── postgresql-cluster.yaml          # CloudNativePG Cluster resource (managed by ArgoCD)
├── apps/                     # ArgoCD Application manifests (GitOps)
│   ├── root.yaml             # Root app that bootstraps all other apps
│   ├── kube-prometheus-stack.yaml  # Prometheus + Grafana monitoring stack
│   ├── http-canary.yaml      # HTTP canary app with custom Prometheus metrics
│   ├── cloudnativepg-operator.yaml  # CloudNativePG operator (cnpg-system)
│   └── postgresql.yaml       # PostgreSQL cluster via CloudNativePG (postgresql)
└── src/
    └── http-canary/          # Source for the http-canary Docker image (published to Docker Hub)
```

## Bootstrap Sequence

`task deploy` runs the following in order:

1. **Terraform apply** — provisions EKS cluster, VPC, IAM roles, ALB security group
2. **kubeconfig** — updates `~/.kube/config` for the new cluster
3. **wait-for-nodes** — waits until all nodes are `Ready`
4. **helm-install-lbc** — installs AWS Load Balancer Controller into `kube-system` with IRSA
5. **helm-install-cluster-autoscaler** — installs Cluster Autoscaler into `kube-system` with IRSA
6. **helm-install-ebs-csi** — installs AWS EBS CSI Driver into `kube-system` with IRSA
7. **helm-install-efs-csi** — installs AWS EFS CSI Driver into `kube-system` with IRSA
8. **helm-install-secrets-manager-csi** — installs Secrets Store CSI Driver (with AWS provider) into `kube-system`
9. **helm-install-argocd** — installs ArgoCD into `argocd` namespace
10. **apply-argocd-ingress** — creates ALB ingress for ArgoCD at `/argocd`
11. **apply-grafana-ingress** — creates ALB ingress for Grafana at `/grafana`
12. **apply-gp3-storage-class** — sets gp3 as default StorageClass (replaces gp2)
13. **apply-io2-storage-class** — applies io2 StorageClass for high-performance workloads
14. **apply-efs-storage-class** — applies EFS StorageClass
15. **install-volume-snapshot-crds** — installs VolumeSnapshot CRDs and snapshot controller
16. **apply-ebs-volume-snapshot-class** — applies EBS VolumeSnapshotClass
17. **apply-fake-api-key-secret-provider-class** — applies SecretProviderClass for Secrets Manager demo
18. **bootstrap-argocd** — applies `apps/root.yaml` to kick off GitOps sync

## Tear Down

`task destroy` runs a safe multi-stage teardown to avoid orphaned AWS resources:

1. Delete ArgoCD root app and wait for all app cleanup (up to 5m + 30s)
2. Delete ArgoCD and Grafana ingresses → wait 300s for ALB deregistration
3. Drain all nodes → wait 90s for VPC CNI cleanup → destroy the managed node group
4. `terraform destroy` — removes remaining AWS resources
5. Clean up any orphaned ENIs tagged with the cluster name

## Adding Applications (GitOps)

The `apps/root.yaml` root Application is the only manifest applied manually via `kubectl` (during `task deploy`). It implements the [app of apps](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/) pattern — ArgoCD watches the `apps/` directory and automatically syncs any new `Application` manifests committed there.

To add a new application, commit an ArgoCD `Application` manifest to `apps/` and push — no `kubectl apply` needed. ArgoCD will detect and sync it automatically. The `apps/http-canary.yaml` is a working example.

## Infrastructure Module

Terraform uses the [`ccliver/k8s-lab/aws`](https://registry.terraform.io/modules/ccliver/k8s-lab/aws) module (v1.14.1). Remote state is stored in S3 with native S3 lock file support. Backend configuration is kept in a gitignored `terraform/backend.hcl` — copy `terraform/backend.hcl.example` and fill in your own bucket details before deploying.

## Pre-commit Hooks

```bash
pre-commit run --all-files
```

Enforces `terraform fmt`, `terraform validate`, `tflint`, merge-conflict detection, and trailing newlines before every commit.
