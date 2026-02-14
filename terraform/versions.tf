terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }
  }
}
