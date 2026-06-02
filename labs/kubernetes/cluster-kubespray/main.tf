provider "google" {
  project = var.project_id
  region  = var.region
  # auth: GOOGLE_OAUTH_ACCESS_TOKEN из `gcloud auth print-access-token`
}

# ─── Сеть ───────────────────────────────────────────────────────────────────
resource "google_compute_network" "net" {
  name                    = "kubespray-net"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "kubespray-subnet"
  region        = var.region
  network       = google_compute_network.net.id
  ip_cidr_range = "10.10.0.0/24"
}

# Полная связность между нодами кластера (etcd, kubelet, CNI, API и т.д.)
resource "google_compute_firewall" "internal" {
  name      = "kubespray-internal"
  network   = google_compute_network.net.id
  allow { protocol = "all" }
  source_ranges = ["10.10.0.0/24"]
}

# Снаружи: SSH (Ansible) + kube-apiserver + ICMP
resource "google_compute_firewall" "external" {
  name    = "kubespray-external"
  network = google_compute_network.net.id
  allow {
    protocol = "tcp"
    ports    = ["22", "6443"]
  }
  allow { protocol = "icmp" }
  source_ranges = ["0.0.0.0/0"]
}

# ─── Ноды ───────────────────────────────────────────────────────────────────
resource "google_compute_instance" "node" {
  for_each     = var.nodes
  name         = each.key
  machine_type = var.machine_type
  zone         = var.zone

  # роль (control-plane/worker) — в label, чтобы потом сгенерировать inventory
  labels = {
    role = each.value
  }

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = var.disk_size_gb
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id
    access_config {} # внешний IP для SSH с control-машины
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${file(var.ssh_pubkey_path)}"
  }

  # Kubespray требует выключенный swap и br_netfilter — это делает сам playbook,
  # но базовый образ Ubuntu 22.04 уже подходит.
}
