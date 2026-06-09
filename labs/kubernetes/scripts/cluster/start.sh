#!/usr/bin/env bash
# Запуск ОСТАНОВЛЕННЫХ VM стенда + обновление внешних IP (~3-5 мин).
# При stop/start GCE меняет внешние IP (внутренние стабильны — кластер внутри
# себя цел), поэтому после старта нужно: обновить terraform state, inventory
# Kubespray и server в kubeconfig. Всё это делает этот скрипт.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TF_DIR="$ROOT_DIR/cluster-kubespray"
KUBESPRAY_DIR="${KUBESPRAY_DIR:-/root/kubespray}"
INVENTORY="$KUBESPRAY_DIR/inventory/labcluster/hosts.yaml"
KCONF="${KCONF:-/root/.kube/kubespray.conf}"
SSH_KEY="${SSH_KEY:-/root/.ssh/kubespray}"
SSH_OPTS=(-i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes)

GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth print-access-token)"
export GOOGLE_OAUTH_ACCESS_TOKEN

PROJECT="$(terraform -chdir="$TF_DIR" output -raw project_id 2>/dev/null \
  || python3 -c "import re;print(re.search(r'project_id\"\s*\{[^}]*default\s*=\s*\"([^\"]+)',open('$TF_DIR/variables.tf').read(),re.S).group(1))")"
ZONE="$(terraform -chdir="$TF_DIR" output -raw zone 2>/dev/null \
  || python3 -c "import re;print(re.search(r'\"zone\"\s*\{[^}]*default\s*=\s*\"([^\"]+)',open('$TF_DIR/variables.tf').read(),re.S).group(1))")"
mapfile -t NODE_NAMES < <(terraform -chdir="$TF_DIR" output -json nodes \
  | python3 -c 'import json,sys;[print(k) for k in json.load(sys.stdin)]')

echo "=== Старт VM: ${NODE_NAMES[*]} ==="
gcloud compute instances start "${NODE_NAMES[@]}" --zone="$ZONE" --project="$PROJECT"

echo "=== Обновление state/inventory/kubeconfig (IP сменились) ==="
terraform -chdir="$TF_DIR" apply -refresh-only -input=false -auto-approve >/dev/null
"$TF_DIR/gen-inventory.sh" > "$INVENTORY"

CP_IP="$(terraform -chdir="$TF_DIR" output -json nodes \
  | python3 -c 'import json,sys;[print(v["external"]) for v in json.load(sys.stdin).values() if v["role"]=="control-plane"]')"
for _ in $(seq 1 36); do
  ssh "${SSH_OPTS[@]}" "ubuntu@$CP_IP" 'true' 2>/dev/null && break
  sleep 5
done
ssh "${SSH_OPTS[@]}" "ubuntu@$CP_IP" 'sudo cat /etc/kubernetes/admin.conf' > "$KCONF"
kubectl --kubeconfig "$KCONF" config set-cluster cluster.local \
  --server="https://$CP_IP:6443" --insecure-skip-tls-verify=true >/dev/null
kubectl --kubeconfig "$KCONF" config unset clusters.cluster.local.certificate-authority-data >/dev/null
export KUBECONFIG="$KCONF"

echo "=== Ожидание готовности нод ==="
EXPECTED="${#NODE_NAMES[@]}"
for _ in $(seq 1 36); do
  READY="$(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l)"
  [[ "$READY" -eq "$EXPECTED" ]] && break
  sleep 5
done
kubectl get nodes -o wide
echo
echo "Готово. export KUBECONFIG=$KCONF  (новый IP control-plane: $CP_IP)"
