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

resource "aws_secretsmanager_secret" "fake_api_key" {
  name                    = "${local.project}-fake-api-key"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "fake_api_key" {
  secret_id     = aws_secretsmanager_secret.fake_api_key.id
  secret_string = "D8B69013-764D-40C1-B3E3-C69989CF1343"
}

data "aws_iam_policy_document" "k8s_lab_status_trust" {
  statement {
    principals {
      type        = "Federated"
      identifiers = [module.k8s_lab.oidc_provider_arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${module.k8s_lab.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "${module.k8s_lab.oidc_provider}:sub"
      values   = ["system:serviceaccount:k8s-lab-status:k8s-lab-status"]
    }
  }
}

resource "aws_iam_role" "k8s_lab_status" {
  name               = "${local.project}-status"
  assume_role_policy = data.aws_iam_policy_document.k8s_lab_status_trust.json
}

data "aws_iam_policy_document" "k8s_lab_status" {
  statement {
    actions = [
      "secretsmanager:GetSecretValue",
    ]
    resources = [aws_secretsmanager_secret.fake_api_key.arn]
  }
}

data "aws_vpc" "k8s_lab" {
  id = module.k8s_lab.vpc_id
}

resource "aws_iam_role_policy" "k8s_lab_status" {
  name   = "k8s-lab-status-policy"
  role   = aws_iam_role.k8s_lab_status.id
  policy = data.aws_iam_policy_document.k8s_lab_status.json
}

module "k8s_lab" {
  source  = "ccliver/k8s-lab/aws"
  version = "1.21.2"

  use_eks                        = true
  project                        = local.project
  endpoint_public_access_cidrs   = var.endpoint_public_access_cidrs
  eks_min_size                   = 3
  eks_max_size                   = 6
  instance_types                 = ["t4g.medium"]
  kubernetes_version             = "1.34"
  eks_capacity_type              = "ON_DEMAND"
  eks_node_group_ami_type        = "AL2023_ARM_64_STANDARD"
  deploy_aws_lbc_role            = true
  alb_allowed_cidrs              = var.alb_allowed_cidrs
  deploy_cluster_autoscaler_role = true
  deploy_ebs_csi_role            = true
  deploy_efs_csi_role            = true
}
