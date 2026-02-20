provider "aws" {
  region = "us-east-1"
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
  instance_types               = ["t4g.medium"]
  kubernetes_version           = "1.34"
  eks_capacity_type            = "SPOT"
  eks_node_group_ami_type      = "AL2023_ARM_64_STANDARD"
  deploy_aws_lbc_role          = true
  alb_allowed_cidrs            = var.alb_allowed_cidrs
}
