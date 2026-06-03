#!/usr/bin/env bash
# app-controller.sh — учебный оператор для CRD WebApp (lab.example.com/v1).
#
# Демонстрирует ОПЕРАТОР-ПАТТЕРН минимальными средствами (kubectl + jq), без kopf/
# controller-runtime. Reconcile-петля level-triggered (см. теорию модуля 19):
#   для КАЖДОГО WebApp X в namespace:
#     1. observe desired  — spec.image, spec.replicas из CR;
#     2. act (идемпотентно) — `kubectl apply` Deployment <X>-deploy и Service <X>-svc;
#     3. write status      — status.availableReplicas через subresource /status.
# Удаление НЕ обрабатывается явно: на созданные объекты ставится ownerReference на
# WebApp, поэтому при `kubectl delete webapp X` их каскадно сносит garbage collector.
#
# Запуск (на control-машине, использует текущий KUBECONFIG):
#   export KUBECONFIG=/root/.kube/kubespray.conf
#   bash app-controller.sh                 # Ctrl+C для остановки
# Параметры через env: WEBAPP_NS (default lab), RECONCILE_INTERVAL (default 5s).
#
# ВАЖНО: НЕ `set -e` — единичная ошибка одного reconcile не должна ронять весь
# контроллер (устойчивость к краевым случаям — требование задачи).
set -uo pipefail

NS="${WEBAPP_NS:-lab}"
INTERVAL="${RECONCILE_INTERVAL:-5}"
GROUP="lab.example.com"

log() { echo "$(date +%H:%M:%S) [webapp-controller] $*"; }

# Привести один WebApp (JSON в $1) к желаемому состоянию.
reconcile_one() {
  local cr="$1" name image replicas uid dep svc avail
  name=$(jq -r '.metadata.name'    <<<"$cr")
  image=$(jq -r '.spec.image'      <<<"$cr")
  replicas=$(jq -r '.spec.replicas'<<<"$cr")
  uid=$(jq -r '.metadata.uid'      <<<"$cr")
  dep="${name}-deploy"; svc="${name}-svc"

  # Deployment <name>-deploy. ownerReference -> WebApp: каскадное удаление через GC.
  if ! kubectl -n "$NS" apply -f - >/dev/null 2>&1 <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${dep}
  labels: { app: ${name}, app.kubernetes.io/managed-by: webapp-controller }
  ownerReferences:
  - apiVersion: ${GROUP}/v1
    kind: WebApp
    name: ${name}
    uid: ${uid}
    controller: true
    blockOwnerDeletion: true
spec:
  replicas: ${replicas}
  selector: { matchLabels: { app: ${name} } }
  template:
    metadata: { labels: { app: ${name} } }
    spec:
      containers:
      - name: app
        image: "${image}"
        ports: [{ containerPort: 80 }]
EOF
  then log "WARN: apply deploy/${dep} не удался (пропускаю цикл)"; return 1; fi

  # Service <name>-svc на :80.
  if ! kubectl -n "$NS" apply -f - >/dev/null 2>&1 <<EOF
apiVersion: v1
kind: Service
metadata:
  name: ${svc}
  labels: { app: ${name}, app.kubernetes.io/managed-by: webapp-controller }
  ownerReferences:
  - apiVersion: ${GROUP}/v1
    kind: WebApp
    name: ${name}
    uid: ${uid}
    controller: true
    blockOwnerDeletion: true
spec:
  selector: { app: ${name} }
  ports: [{ port: 80, targetPort: 80 }]
EOF
  then log "WARN: apply svc/${svc} не удался (пропускаю цикл)"; return 1; fi

  # Замкнуть reconcile: записать фактические доступные реплики в status CR.
  avail=$(kubectl -n "$NS" get deploy "$dep" -o jsonpath='{.status.availableReplicas}' 2>/dev/null)
  avail="${avail:-0}"
  kubectl -n "$NS" patch webapp "$name" --subresource=status --type=merge \
    -p "{\"status\":{\"availableReplicas\":${avail}}}" >/dev/null 2>&1 || true

  log "reconciled ${name}: ${dep}(replicas=${replicas}, image=${image}, available=${avail}) + ${svc}"
}

command -v jq >/dev/null || { echo "нужен jq"; exit 1; }
log "start: namespace=${NS}, interval=${INTERVAL}s (Ctrl+C — стоп)"
while true; do
  list=$(kubectl -n "$NS" get webapps -o json 2>/dev/null) \
    || { log "WARN: list webapps не удался, повтор через ${INTERVAL}s"; sleep "$INTERVAL"; continue; }
  count=$(jq '.items | length' <<<"$list" 2>/dev/null || echo 0)
  for ((i=0; i<count; i++)); do
    reconcile_one "$(jq -c ".items[$i]" <<<"$list")"
  done
  sleep "$INTERVAL"
done
