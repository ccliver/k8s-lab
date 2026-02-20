# k8s-lab

A Kubernetes lab on AWS EKS for CKA studying and exploring tools in the Kubernetes ecosystem. Infrastructure is managed with Terraform and a [Taskfile](https://taskfile.dev) runner. GitOps is handled by ArgoCD.

## Architecture

```
                        ┌──────────────────────────────────────────┐
                        │                  AWS                     │
                        │                                          │
                        │   ┌──────────────────────────────────┐   │
                        │   │            EKS (k8s-lab)         │   │
                        │   │  K8s 1.34 · t4g.small · 2-3 nodes│   │
                        │   │  SPOT · ARM/Graviton · AL2023    │   │
                        │   │                                  │   │
  Browser ──── ALB ─────┼───┤  /argocd  → ArgoCD               │   │
  (HTTP:80)  (shared)   │   │  /grafana → Grafana              │   │
                        │   │                                  │   │
                        │   │  AWS Load Balancer Controller    │   │
                        │   │  kube-prometheus-stack           │   │
                        │   └──────────────────────────────────┘   │
                        │                                          │
                        │  S3 (Terraform state) · IAM (IRSA)       │
                        └──────────────────────────────────────────┘
```

ArgoCD and Grafana share a single internet-facing ALB via an IngressGroup (`lab`), path-routed at `/argocd` and `/grafana`.

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
task alb_dns
# ArgoCD → http://<alb-dns>/argocd
# Grafana → http://<alb-dns>/grafana

# 4. Retrieve default passwords
task argocd-password
task grafana-password
```

## Available Tasks

```
task deploy            Deploy lab (Terraform + Helm + ingress)
task destroy           Tear down lab (order-safe multi-stage)
task plan              Show Terraform plan
task kubeconfig        Add/update cluster in ~/.kube/config
task alb_dns           Print the ALB DNS name
task argocd-pf         Port-forward ArgoCD UI → http://127.0.0.1:8080
task argocd-password   Retrieve ArgoCD admin password
task grafana-password  Retrieve Grafana admin password
```

## Repository Layout

```
.
├── Taskfile.yml              # All day-to-day operations
├── terraform/                # AWS infrastructure (EKS, VPC, IAM, ALB SG)
│   ├── main.tf               # ccliver/k8s-lab/aws module call
│   ├── variables.tf          # endpoint_public_access_cidrs, alb_allowed_cidrs
│   ├── output.tf             # aws_lbc_role_arn, vpc_id, alb_security_group_id
│   ├── backend.tf            # S3 remote state (us-east-1)
│   └── versions.tf           # Terraform >= 1.0, AWS ~> 6
├── manifests/                # Raw K8s manifests applied by Taskfile
│   ├── argocd-ingress.yaml   # ArgoCD ALB ingress (envsubst for SG ID)
│   └── grafana-ingress.yaml  # Grafana ALB ingress (envsubst for SG ID)
└── argocd-apps/              # ArgoCD Application manifests (GitOps)
    └── nginx/nginx.yaml      # Sample nginx deployment (2 replicas)
```

## Bootstrap Sequence

`task deploy` runs the following in order:

1. **Terraform apply** — provisions EKS cluster, VPC, IAM roles, ALB security group
2. **kubeconfig** — updates `~/.kube/config` for the new cluster
3. **wait-for-nodes** — waits until all nodes are `Ready`
4. **helm-install-lbc** — installs AWS Load Balancer Controller into `kube-system` with IRSA
5. **helm-install-argocd** — installs ArgoCD into `argocd` namespace
6. **apply-argocd-ingress** — creates ALB ingress for ArgoCD at `/argocd`
7. **apply-grafana-ingress** — creates ALB ingress for Grafana at `/grafana`

## Tear Down

`task destroy` runs a safe multi-stage teardown to avoid orphaned AWS resources:

1. Delete ArgoCD and Grafana ingresses → wait 300s for ALB deregistration
2. Drain all nodes → wait 90s for VPC CNI cleanup → destroy the managed node group
3. `terraform destroy` — removes remaining AWS resources
4. Clean up any orphaned ENIs tagged with the cluster name

## Adding Applications (GitOps)

Drop an ArgoCD `Application` manifest into `argocd-apps/` and apply it:

```bash
kubectl apply -f argocd-apps/<your-app>/app.yaml
```

ArgoCD will pick it up and sync the target repo/path to the cluster. The `nginx` app under `argocd-apps/nginx/` is a working example.

## Infrastructure Module

Terraform uses the [`ccliver/k8s-lab/aws`](https://registry.terraform.io/modules/ccliver/k8s-lab/aws) module (v1.13.3). Remote state is stored in S3 with native S3 lock file support. Backend configuration is kept in a gitignored `terraform/backend.hcl` — copy `terraform/backend.hcl.example` and fill in your own bucket details before deploying.

## Pre-commit Hooks

```bash
pre-commit run --all-files
```

Enforces `terraform fmt`, `terraform validate`, `tflint`, merge-conflict detection, and trailing newlines before every commit.
