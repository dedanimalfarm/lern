#!/usr/bin/env bash
# Генерирует Kubespray inventory (hosts.yaml) из `terraform output nodes`.
# Использование:
#   ./gen-inventory.sh > /root/kubespray/inventory/labcluster/hosts.yaml
set -euo pipefail
cd "$(dirname "$0")"

terraform output -json nodes | python3 -c '
import json, sys
nodes = json.load(sys.stdin)
cp      = [k for k, v in nodes.items() if v["role"] == "control-plane"]
workers = [k for k, v in nodes.items() if v["role"] == "worker"]

print("all:")
print("  vars:")
print("    ansible_user: ubuntu")
print("    ansible_ssh_private_key_file: /root/.ssh/kubespray")
print("    ansible_become: true")
print("  hosts:")
for k, v in nodes.items():
    print(f"    {k}:")
    print(f"      ansible_host: {v[\"external\"]}")
    print(f"      ip: {v[\"internal\"]}")
    print(f"      access_ip: {v[\"internal\"]}")
print("  children:")
print("    kube_control_plane:")
print("      hosts:")
for k in cp:
    print(f"        {k}:")
print("    kube_node:")
print("      hosts:")
for k in workers:
    print(f"        {k}:")
print("    etcd:")
print("      hosts:")
for k in cp:
    print(f"        {k}:")
print("    k8s_cluster:")
print("      children:")
print("        kube_control_plane:")
print("        kube_node:")
print("    calico_rr:")
print("      hosts: {}")
'
