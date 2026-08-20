provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = {
      Project = local.project
    }
  }
}

locals {
  project = "k8s-lab"
}

module "k8s_lab" {
  source  = "ccliver/k8s-lab/aws"
  version = "1.27.1"

  use_eks                        = true
  project                        = local.project
  endpoint_public_access_cidrs   = var.endpoint_public_access_cidrs
  eks_min_size                   = 3
  eks_max_size                   = 6
  instance_types                 = ["t4g.medium"]
  kubernetes_version             = "1.36"
  eks_capacity_type              = "ON_DEMAND"
  eks_node_group_ami_type        = "AL2023_ARM_64_STANDARD"
  deploy_aws_lbc_role            = true
  alb_allowed_cidrs              = var.alb_allowed_cidrs
  deploy_cluster_autoscaler_role = true
  deploy_ebs_csi_role            = true
  deploy_efs_csi_role            = true
  use_pod_identity               = true
}

resource "aws_eks_addon" "cert_manager" {
  cluster_name = local.project
  addon_name   = "cert-manager"
  depends_on   = [module.k8s_lab]
}

resource "aws_eks_addon" "adot" {
  cluster_name = local.project
  addon_name   = "adot"
  depends_on   = [aws_eks_addon.cert_manager]
}
