output "nodes" {
  description = "Имя -> внешний/внутренний IP и роль (для Kubespray inventory)."
  value = {
    for k, n in google_compute_instance.node : k => {
      role     = n.labels.role
      external = n.network_interface[0].access_config[0].nat_ip
      internal = n.network_interface[0].network_ip
    }
  }
}

output "ssh_hint" {
  value = "ssh -i /root/.ssh/kubespray ${var.ssh_user}@<external-ip>"
}

# Для scripts/cluster/*.sh: project/zone без парсинга variables.tf.
output "project_id" {
  value = var.project_id
}

output "zone" {
  value = var.zone
}
