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

locals {
  project = "k8s-lab"
}


module "k8s_lab" {
  source  = "ccliver/k8s-lab/aws"
  version = "1.12.2"

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
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  set = [
    {
      name  = "clusterName"
      value = local.project
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = module.k8s_lab.aws_lbc_role_arn
    }
  ]
}
