variable "project_id" {
  type    = string
  default = "k8s-lab-test-352440"
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}

variable "machine_type" {
  type        = string
  description = "e2-medium = 2 vCPU / 4 GB — минимум, на котором Kubespray-нода стабильна."
  default     = "e2-medium"
}

variable "disk_size_gb" {
  type    = number
  default = 30
}

variable "ssh_user" {
  type    = string
  default = "ubuntu"
}

variable "ssh_pubkey_path" {
  type    = string
  default = "/root/.ssh/kubespray.pub"
}

# Узлы кластера: 1 control-plane + 2 worker (минимальный multi-node для лабы).
variable "nodes" {
  type    = map(string)
  default = {
    "k8s-cp-1" = "control-plane"
    "k8s-w-1"  = "worker"
    "k8s-w-2"  = "worker"
  }
}
