provider "aws" {
  region = "us-east-1"
}

provider "helm" {
  kubernetes = {
    host                   = module.k8s_lab.cluster_endpoint
    cluster_ca_certificate = base64decode(module.k8s_lab.cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", local.project]
      command     = "aws"
    }
  }
}

provider "kubernetes" {
  host                   = module.k8s_lab.cluster_endpoint
  cluster_ca_certificate = base64decode(module.k8s_lab.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", local.project]
    command     = "aws"
  }
}

locals {
  project = "k8s-lab"
}


module "k8s_lab" {
  source  = "ccliver/k8s-lab/aws"
  version = "1.13.3"

  use_eks                      = true
  project                      = local.project
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs
  eks_min_size                 = 2
  eks_max_size                 = 3
  instance_types               = ["t4g.small"]
  kubernetes_version           = "1.34"
  eks_capacity_type            = "SPOT"
  eks_node_group_ami_type      = "AL2023_ARM_64_STANDARD"
  deploy_aws_lbc_role          = true
  alb_allowed_cidrs            = var.alb_allowed_cidrs
}

resource "time_sleep" "wait_for_cluster" {
  depends_on = [
    module.k8s_lab,
  ]

  create_duration = "180s"
}

resource "helm_release" "aws_load_balancer_controller" {
  name          = "aws-load-balancer-controller"
  repository    = "https://aws.github.io/eks-charts"
  chart         = "aws-load-balancer-controller"
  namespace     = "kube-system"
  atomic        = true
  wait          = true
  wait_for_jobs = true

  set = [
    {
      name  = "clusterName"
      value = local.project
    },
    {
      name  = "serviceAccount.create"
      value = true
    },
    {
      name  = "serviceAccount.name"
      value = "aws-load-balancer-controller"
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = module.k8s_lab.aws_lbc_role_arn
    },
    {
      # https://repost.aws/questions/QUG4ZL40hnRFas7ZgLXcQvoQ/al2023-ami-upgrade-eks-cluster-aws-load-balancer-error
      name  = "vpcId"
      value = module.k8s_lab.vpc_id
    }
  ]

  depends_on = [module.k8s_lab, time_sleep.wait_for_cluster]
}

resource "helm_release" "argocd" {
  name             = "argo-cd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  timeout          = 600
  wait             = true
  wait_for_jobs    = true
  atomic           = true

  values = [
    yamlencode({
      server = {
        service = {
          type = "ClusterIP"
        }
        ingress = {
          enabled = false
        }
        extraArgs = [
          "--insecure" # Disables TLS and redirect
        ]
      }
    })
  ]

  depends_on = [module.k8s_lab, helm_release.aws_load_balancer_controller]
}

resource "kubernetes_ingress_v1" "argocd" {
  metadata {
    name      = "argocd-server"
    namespace = "argocd"
    annotations = {
      "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"      = "ip"
      "alb.ingress.kubernetes.io/security-groups"  = module.k8s_lab.alb_security_group_id
      "alb.ingress.kubernetes.io/listen-ports"     = "[{\"HTTP\":80}]"
      "alb.ingress.kubernetes.io/healthcheck-path" = "/healthz"
      "alb.ingress.kubernetes.io/healthcheck-port" = "8080"
      "kubernetes.io/ingress.class"                = "alb"
    }
  }

  spec {
    ingress_class_name = "alb"

    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = "argo-cd-argocd-server"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.argocd]
}
