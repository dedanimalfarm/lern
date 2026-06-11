#!/usr/bin/env bash
# Полный подъём лабораторного стенда одной командой (~25 мин):
#   VM (Terraform) → inventory → Kubespray → kubeconfig → bootstrap лабы.
# Идемпотентен: на уже поднятом кластере Terraform и bootstrap — no-op,
# Kubespray переиграет роли без разрушения (но потратит ~15 мин).
#
# Использование:
#   ./up.sh             # кластер + bootstrap (ns, квоты, metrics-server, storage)
#   ./up.sh --stacks    # + стеки наблюдаемости (kube-prometheus-stack, Loki)
#   ./up.sh --addons    # --stacks + ВСЕ persistent-аддоны лабы (ingress-nginx,
#                       #   Argo CD, cert-manager, sealed-secrets, ESO, VSO+Vault,
#                       #   Envoy Gateway) — полное восстановление стенда
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TF_DIR="$ROOT_DIR/cluster-kubespray"
KUBESPRAY_DIR="${KUBESPRAY_DIR:-/root/kubespray}"
INVENTORY="$KUBESPRAY_DIR/inventory/labcluster/hosts.yaml"
KCONF="${KCONF:-/root/.kube/kubespray.conf}"
SSH_KEY="${SSH_KEY:-/root/.ssh/kubespray}"
SSH_OPTS=(-i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes)
AUTOSTOP_POLICY="${AUTOSTOP_POLICY:-lab-autostop}"

echo "=== [1/6] Terraform: VM + сеть ==="
GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth print-access-token)"
export GOOGLE_OAUTH_ACCESS_TOKEN
terraform -chdir="$TF_DIR" init -input=false >/dev/null
terraform -chdir="$TF_DIR" apply -input=false -auto-approve

# Параметры проекта — из terraform-переменных (single source of truth).
PROJECT="$(terraform -chdir="$TF_DIR" output -raw project_id 2>/dev/null \
  || python3 -c "import re;print(re.search(r'project_id\"\s*\{[^}]*default\s*=\s*\"([^\"]+)',open('$TF_DIR/variables.tf').read(),re.S).group(1))")"
ZONE="$(python3 -c "import re;print(re.search(r'\"zone\"\s*\{[^}]*default\s*=\s*\"([^\"]+)',open('$TF_DIR/variables.tf').read(),re.S).group(1))")"

mapfile -t ALL_IPS < <(terraform -chdir="$TF_DIR" output -json nodes \
  | python3 -c 'import json,sys;[print(v["external"]) for v in json.load(sys.stdin).values()]')
CP_IP="$(terraform -chdir="$TF_DIR" output -json nodes \
  | python3 -c 'import json,sys;[print(v["external"]) for v in json.load(sys.stdin).values() if v["role"]=="control-plane"]')"
mapfile -t NODE_NAMES < <(terraform -chdir="$TF_DIR" output -json nodes \
  | python3 -c 'import json,sys;[print(k) for k in json.load(sys.stdin)]')

echo "=== [2/6] Inventory + SSH + отключение unattended-upgrades ==="
"$TF_DIR/gen-inventory.sh" > "$INVENTORY"
for ip in "${ALL_IPS[@]}"; do
  for _ in $(seq 1 24); do
    ssh "${SSH_OPTS[@]}" "ubuntu@$ip" 'true' 2>/dev/null && break
    sleep 5
  done
  # apt-lock от unattended-upgrades роняет Kubespray по таймауту 300с —
  # обязательный шаг на свежих Ubuntu-VM (см. README cluster-kubespray).
  ssh "${SSH_OPTS[@]}" "ubuntu@$ip" \
    'sudo systemctl stop unattended-upgrades apt-daily.timer apt-daily-upgrade.timer 2>/dev/null; sudo systemctl disable unattended-upgrades 2>/dev/null; true'
  echo "  $ip: ssh ok, apt-timers off"
done

echo "=== [3/6] Kubespray (~15 мин) ==="
( cd "$KUBESPRAY_DIR" && \
  ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i "$INVENTORY" cluster.yml -b )

echo "=== [4/6] kubeconfig ==="
ssh "${SSH_OPTS[@]}" "ubuntu@$CP_IP" 'sudo cat /etc/kubernetes/admin.conf' > "$KCONF"
# apiserver-cert не содержит внешний IP → insecure-skip (см. README cluster-kubespray)
kubectl --kubeconfig "$KCONF" config set-cluster cluster.local \
  --server="https://$CP_IP:6443" --insecure-skip-tls-verify=true >/dev/null
kubectl --kubeconfig "$KCONF" config unset clusters.cluster.local.certificate-authority-data >/dev/null
export KUBECONFIG="$KCONF"
kubectl get nodes -o wide

echo "=== [5/6] Bootstrap лабы ==="
bash "$ROOT_DIR/scripts/bootstrap/00-create-namespaces.sh"
bash "$ROOT_DIR/scripts/bootstrap/01-apply-quotas.sh"
bash "$ROOT_DIR/scripts/bootstrap/02-install-metrics-server.sh"
# Storage обязателен в базовом наборе: без default-StorageClass любой PVC без
# storageClassName виснет в Pending (модули 03/05/21 и др.). Скрипт не только
# ставит local-path, но и вешает аннотацию is-default-class — установка «голым
# манифестом» её НЕ содержит (на этом уже горели: baseline-QA m05 FAIL).
bash "$ROOT_DIR/scripts/bootstrap/05-install-storage.sh"

echo "=== [6/6] Авто-стоп VM (экономия) ==="
# Policy lab-autostop — региональный ресурс, переживает destroy VM; привязку
# к свежесозданным VM нужно повторять. Отсутствие policy — не фатально.
for n in "${NODE_NAMES[@]}"; do
  gcloud compute instances add-resource-policies "$n" \
    --resource-policies="$AUTOSTOP_POLICY" --zone="$ZONE" --project="$PROJECT" \
    >/dev/null 2>&1 && echo "  $n: $AUTOSTOP_POLICY attached" \
    || echo "  $n: policy уже привязана или отсутствует (см. docs/ROADMAP/CLAUDE.md)"
done

if [[ "${1:-}" == "--stacks" || "${1:-}" == "--addons" ]]; then
  echo "=== [extra] Стеки наблюдаемости (модули 17/18) ==="
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
  helm repo update >/dev/null
  helm upgrade --install kps prometheus-community/kube-prometheus-stack \
    -n monitoring --create-namespace --wait --timeout 10m
  kubectl apply -f "$ROOT_DIR/modules/18-centralized-logging/manifests/"
fi

if [[ "${1:-}" == "--addons" ]]; then
  echo "=== [extra] Persistent-аддоны лабы ==="
  # Порядок не критичен, но Argo CD дольше всех раскатывается — первым.
  # Без этих аддонов модули 09/16/22/23/25 и capstone падают в QA.
  for s in 06-install-argocd.sh 03-install-ingress.sh 07-install-cert-manager.sh \
           08-install-sealed-secrets.sh 09-install-external-secrets.sh \
           10-install-vault-secrets-operator.sh 11-install-gateway-api.sh; do
    bash "$ROOT_DIR/scripts/bootstrap/$s"
  done
fi

echo
echo "Готово. export KUBECONFIG=$KCONF"
echo "Стенд останавливается по расписанию policy '$AUTOSTOP_POLICY'; вручную: scripts/cluster/stop.sh"
