# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

A Kubernetes lab environment on AWS EKS with ArgoCD for GitOps. Infrastructure is managed via Terraform and a [Taskfile](https://taskfile.dev) runner. AWS profile `lab` is used by default.

## Common Commands

All day-to-day operations use `task` (Taskfile runner):

```bash
task deploy           # full deploy: terraform + helm + ingresses + ArgoCD bootstrap
task destroy          # multi-stage teardown (see below)
task tf-plan          # terraform plan
task kubeconfig       # update ~/.kube/config for the cluster

task argocd-pf            # port-forward ArgoCD UI to http://127.0.0.1:8080
task k8s-lab-status-pf    # port-forward k8s-lab-status app
task argocd-password      # retrieve ArgoCD admin password
task grafana-password     # retrieve Grafana admin password
task alb-dns              # print ALB DNS name
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
  - Nodes: `t4g.medium` SPOT, ARM/Graviton, AL2023, min 3 / max 6

`terraform/output.tf` exposes `aws_lbc_role_arn`, `vpc_id`, `alb_security_group_id`, `cluster_autoscaler_role_arn`, and `ebs_csi_role_arn` — these are consumed by Taskfile tasks at deploy time via `terraform output -raw`.

### Bootstrap / Destroy Sequences

See `Taskfile.yml` for the full ordered task sequences. `task deploy` and `task destroy` are order-sensitive — don't reorder steps.

### GitOps / Applications

`apps/` contains ArgoCD `Application` manifests (app-of-apps pattern). `manifests/` contains raw Kubernetes manifests — ingresses and StorageClasses are applied by the Taskfile; everything else is managed by ArgoCD. See the directory for current contents.

`src/http-canary/` holds the Python source and Dockerfile for the `ccliver/http-canary` Docker image. Build and publish with `task publish-http-canary` (supports multi-arch: amd64 + arm64).

## Provider Versions

- Terraform `>= 1.0`
- AWS `~> 6`

## Pre-commit Hooks

`.pre-commit-config.yaml` enforces `terraform fmt`, `terraform validate`, `tflint`, merge-conflict checks, and EOF newlines on every commit.

## Documentation Policy

When manifests, Taskfile tasks, or Terraform resources change, check whether `README.md` and `CLAUDE.md` need updating — file trees, bootstrap sequences, task lists, and architecture descriptions should stay in sync with reality. Don't wait to be asked.

## Change Boundaries

- **Do not edit code to fix infrastructure state issues** (stale Terraform state, stuck ArgoCD apps, cluster state). Ask the user first — they usually prefer to handle these manually.
- Prefer minimal, targeted changes. A bug fix doesn't need surrounding refactors; a manifest addition doesn't need restructuring of other files.

## Docker & CI Notes

- Nodes are `t4g.medium` ARM/Graviton running AL2023 — use `dnf`/`yum`, **not** `apt-get`, in any Dockerfiles targeting these nodes.
- The default `docker` driver does not support multi-platform builds. The `publish-http-canary` task handles this with `docker buildx create --name multiplatform --use`, but replicate this pattern for any new multi-platform builds.
- Always specify `--platform linux/arm64` (or `linux/amd64,linux/arm64` for multi-arch) when building images intended for t4g instances.
