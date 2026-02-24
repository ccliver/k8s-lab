# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

A Kubernetes lab environment on AWS EKS with ArgoCD for GitOps. Infrastructure is managed via Terraform and a [Taskfile](https://taskfile.dev) runner. AWS profile `lab` is used by default.

## Common Commands

All day-to-day operations use `task` (Taskfile runner):

```bash
task deploy        # terraform init + apply
task destroy       # multi-stage teardown (see below)
task plan          # terraform plan
task kubeconfig    # update ~/.kube/config for the cluster

task argocd-pf     # port-forward ArgoCD UI to http://127.0.0.1:8080
task argocd-password  # retrieve ArgoCD admin password
task alb_dns       # print ALB DNS name for ArgoCD
```

Terraform directly (from `terraform/`):

```bash
terraform fmt      # format (also enforced by pre-commit)
terraform validate
```

Pre-commit (run before committing):

```bash
pre-commit run --all-files
```

## Architecture

### Infrastructure (Terraform)

All Terraform lives in `terraform/`. Remote state is in S3 (`ccliver-k8s-lab-tf-state`, us-east-1) with lock file support. **Terraform manages AWS resources only** — no Helm or Kubernetes providers.

Resources provisioned:
- **EKS cluster** via the `ccliver/k8s-lab/aws` Terraform registry module (cluster name: `k8s-lab`, Kubernetes 1.34)
  - Nodes: `t4g.small` SPOT, ARM/Graviton, AL2023, min 2 / max 3

`terraform/output.tf` exposes `aws_lbc_role_arn`, `vpc_id`, and `alb_security_group_id` — these are consumed by Taskfile tasks at deploy time via `terraform output -raw`.

### Bootstrap Sequence (post-`terraform apply`)

The Taskfile handles all Kubernetes-layer bootstrapping in order:
1. `kubeconfig` — update `~/.kube/config`
2. `wait-for-nodes` — `kubectl wait` until all nodes are Ready
3. `helm-install-lbc` — install AWS Load Balancer Controller into `kube-system` with IRSA annotation from Terraform output
4. `helm-install-argocd` — install ArgoCD into `argocd` namespace, ClusterIP, TLS disabled (`--insecure`)
5. `apply-argocd-ingress` — `envsubst` populates `${ALB_SECURITY_GROUP_ID}` in `manifests/argocd-ingress.yaml` then `kubectl apply`

### Destroy Process

The `task destroy` sequence is order-sensitive to avoid orphaned AWS resources:
1. Delete ArgoCD ingress → wait 300s for ALB deregistration
2. Drain nodes → wait 90s for VPC CNI cleanup → targeted destroy of node group
3. `terraform destroy`
4. Clean up orphaned ENIs (by cluster tag)

### GitOps / Applications

`apps/` holds ArgoCD `Application` manifests. The `nginx/nginx.yaml` is a sample deployment (2 replicas, nginx:alpine).

`manifests/` holds raw Kubernetes manifests applied by the Taskfile. `argocd-ingress.yaml` uses `${ALB_SECURITY_GROUP_ID}` as an `envsubst` placeholder.

## Provider Versions

- Terraform `>= 1.0`
- AWS `~> 6`

## Pre-commit Hooks

`.pre-commit-config.yaml` enforces `terraform fmt`, `terraform validate`, `tflint`, merge-conflict checks, and EOF newlines on every commit.
