terraform {
  backend "s3" {
    bucket       = "ccliver-k8s-lab-tf-state"
    key          = "k8s-lab/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}
