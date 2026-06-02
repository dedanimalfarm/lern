# Terraform для VM под Kubespray-кластер (self-managed k8s через Ansible).
# Обычные Compute Engine VM (не GKE) — их можно stop/start для экономии.
terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}
