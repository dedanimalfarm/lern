# Параметры кластера. Значения по умолчанию рассчитаны на дешёвый учебный стенд
# для прогона лаб из ../modules на настоящем кластере.

variable "project_id" {
  type        = string
  description = "GCP project ID, в котором создаётся кластер. НЕ VPN-проект."
}

variable "region" {
  type        = string
  description = "Регион для VPC/subnet."
  default     = "us-central1"
}

variable "zone" {
  type        = string
  description = <<-EOT
    Зона кластера. Указание ЗОНЫ (а не региона) в location делает кластер
    zonal: один control plane вместо трёх. Это покрывается GKE free tier
    (≈$0 за управление) и дешевле regional.
  EOT
  default     = "us-central1-a"
}

variable "cluster_name" {
  type        = string
  description = "Имя кластера и префикс для VPC/subnet/node-pool."
  default     = "lab-cluster"
}

variable "node_machine_type" {
  type        = string
  description = "Тип нод. e2-medium = 2 vCPU / 4 GB — комфортный минимум под system-поды + лабы."
  default     = "e2-medium"
}

variable "node_count" {
  type        = number
  description = "Число нод в пуле. 2 on-demand для стабильности (выбор пользователя)."
  default     = 2
}

variable "use_spot" {
  type        = bool
  description = <<-EOT
    true => spot-ноды (в разы дешевле, но GCP может вытеснять их в любой момент).
    Для стабильного прогона держим false; для экономии переключить в true.
  EOT
  default     = false
}

variable "disk_size_gb" {
  type        = number
  description = "Размер диска ноды. 30 ГБ достаточно для учебных образов и экономит деньги."
  default     = 30
}
