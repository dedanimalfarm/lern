output "cluster_name" {
  description = "Имя созданного кластера."
  value       = google_container_cluster.primary.name
}

output "location" {
  description = "Зона кластера."
  value       = google_container_cluster.primary.location
}

output "node_pool" {
  description = "Тип и количество нод."
  value       = "${var.node_count} x ${var.node_machine_type} (spot=${var.use_spot})"
}

output "get_credentials_cmd" {
  description = "Команда, чтобы настроить kubectl на этот кластер."
  value = join(" ", [
    "gcloud container clusters get-credentials",
    google_container_cluster.primary.name,
    "--zone", var.zone,
    "--project", var.project_id,
  ])
}

output "endpoint" {
  description = "IP control plane (apiserver)."
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}
