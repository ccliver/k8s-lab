variable "endpoint_public_access_cidrs" {
  description = "List of CIDR blocks which can access the Amazon EKS public API server endpoint"
  type        = list(string)
  default     = []
}

variable "alb_allowed_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to access the ALB provisioned by the AWS Load Balancer Controller"
  default     = []
}
