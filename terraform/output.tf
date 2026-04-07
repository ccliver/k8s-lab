output "aws_lbc_role_arn" {
  description = "IAM role ARN for the AWS Load Balancer Controller service account"
  value       = module.k8s_lab.aws_lbc_role_arn
}

output "vpc_id" {
  description = "VPC ID for the EKS cluster"
  value       = module.k8s_lab.vpc_id
}

output "alb_security_group_id" {
  description = "Security group ID to attach to the ArgoCD ALB ingress"
  value       = module.k8s_lab.alb_security_group_id
}

output "cluster_autoscaler_role_arn" {
  description = "IAM role ARN for the Cluster Autoscaler service account"
  value       = module.k8s_lab.cluster_autoscaler_role_arn
}

output "ebs_csi_role_arn" {
  description = "IAM role ARN for the EBS CSI Driver service account"
  value       = module.k8s_lab.ebs_csi_role_arn
}

output "efs_csi_role_arn" {
  description = "IAM role ARN for the EFS CSI Driver service account"
  value       = module.k8s_lab.efs_csi_role_arn
}

output "efs_file_system_id" {
  description = "The ID of the EFS file system created for the EFS CSI Driver"
  value       = module.k8s_lab.efs_file_system_id
}
