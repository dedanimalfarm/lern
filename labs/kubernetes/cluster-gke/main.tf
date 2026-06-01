provider "google" {
  project = var.project_id
  region  = var.region
  # Аутентификация без интерактивного логина: провайдер читает короткоживущий
  # токен из переменной окружения GOOGLE_OAUTH_ACCESS_TOKEN, которую заполняем
  # через `gcloud auth print-access-token` (см. README). Альтернатива —
  # `gcloud auth application-default login` (ADC).
}

# ─────────────────────────────────────────────────────────────────────────────
# Сеть. Отдельная VPC вместо default — воспроизводимо и не зависит от
# авто-создания default-сети при включении Compute API.
# ─────────────────────────────────────────────────────────────────────────────
resource "google_compute_network" "vpc" {
  name                    = "${var.cluster_name}-vpc"
  auto_create_subnetworks = false # создаём subnet вручную, чтобы задать secondary ranges
}

resource "google_compute_subnetwork" "subnet" {
  name          = "${var.cluster_name}-subnet"
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = "10.10.0.0/16" # диапазон под сами ноды

  # VPC-native кластеру нужны вторичные диапазоны: один под Pod IP, другой под
  # ClusterIP сервисов. Имена ссылаются ниже в ip_allocation_policy.
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.20.0.0/16"
  }
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.30.0.0/16"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Кластер. remove_default_node_pool + отдельный node_pool — рекомендованный
# паттерн: дефолтный пул нельзя гибко менять, поэтому сразу его сносим и
# управляем своим.
# ─────────────────────────────────────────────────────────────────────────────
resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.zone # ЗОНА => zonal-кластер (один control plane, free tier)

  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.subnet.id

  remove_default_node_pool = true
  initial_node_count       = 1

  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Учебный кластер: разрешаем `terraform destroy` без ручного снятия защиты.
  deletion_protection = false

  release_channel {
    channel = "REGULAR"
  }
}

resource "google_container_node_pool" "primary_nodes" {
  name     = "${var.cluster_name}-pool"
  location = var.zone
  cluster  = google_container_cluster.primary.name

  node_count = var.node_count

  node_config {
    machine_type = var.node_machine_type
    spot         = var.use_spot
    disk_size_gb = var.disk_size_gb
    disk_type    = "pd-balanced"

    # cloud-platform scope — чтобы ноды могли тянуть образы из Artifact Registry
    # и писать логи/метрики в Cloud Operations.
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = {
      env = "lab"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}
