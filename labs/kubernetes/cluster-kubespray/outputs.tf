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
