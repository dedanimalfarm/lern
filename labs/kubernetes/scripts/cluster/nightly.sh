#!/usr/bin/env bash
# Ночной регрессионный прогон: поднять стенд -> sweep -> отчёт -> погасить стенд.
#
# Запуск руками:   scripts/cluster/nightly.sh
# По расписанию:   0 3 * * *  /root/lern/labs/kubernetes/scripts/cluster/nightly.sh >> /var/log/k8s-nightly.log 2>&1
#
# Переменные:
#   KEEP_UP=1        не гасить стенд после прогона (по умолчанию гасим — деньги)
#   ONLY='^1[0-9]-'  прогнать только часть модулей (regex по имени, см. sweep.sh)
#   REPORT_DIR       куда складывать отчёты (по умолчанию /root/k8s-lab-handoff/nightly)
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPORT_DIR="${REPORT_DIR:-/root/k8s-lab-handoff/nightly}"
STAMP="$(date '+%Y-%m-%d')"
REPORT="$REPORT_DIR/$STAMP.md"
KEEP_UP="${KEEP_UP:-0}"
export KUBECONFIG="${KUBECONFIG:-/root/.kube/kubespray.conf}"

mkdir -p "$REPORT_DIR"
log() { echo "[$(date '+%H:%M:%S')] $*"; }

cleanup() {
  if [[ "$KEEP_UP" == "1" ]]; then
    log "KEEP_UP=1 — стенд оставлен включённым"
    return
  fi
  log "гашу стенд (stop.sh)"
  bash "$ROOT_DIR/scripts/cluster/stop.sh" >/dev/null 2>&1 || log "WARN: stop.sh не отработал — проверьте VM руками"
}
trap cleanup EXIT

log "=== nightly QA $STAMP ==="

# 1) Поднять стенд. start.sh идемпотентен и сам чинит внешние IP в
#    kubeconfig/inventory после смены при stop/start.
if kubectl --request-timeout=10s get nodes >/dev/null 2>&1; then
  log "кластер уже доступен — start.sh не нужен"
  KEEP_UP=1   # не гасим то, что подняли не мы
else
  log "поднимаю стенд (start.sh, ~5 мин)"
  if ! bash "$ROOT_DIR/scripts/cluster/start.sh" >/dev/null 2>&1; then
    log "FAIL: start.sh не поднял стенд"
    { echo "# Nightly QA $STAMP"; echo; echo "❌ стенд не поднялся (start.sh). Прогон не выполнялся."; } > "$REPORT"
    exit 1
  fi
fi

for _ in $(seq 1 30); do
  kubectl --request-timeout=10s get nodes >/dev/null 2>&1 && break
  sleep 10
done
kubectl --request-timeout=10s get nodes >/dev/null 2>&1 || { log "FAIL: API недоступен"; exit 1; }

NOT_READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -cv ' Ready ' || true)
[[ "$NOT_READY" != "0" ]] && log "WARN: нод не в Ready: $NOT_READY"

# 2) Аддоны стенда — контракт модулей (m16/22/23/25 и capstone падают без них).
log "проверяю persistent-аддоны"
MISSING=()
kubectl get sc -o jsonpath='{.items[*].metadata.annotations}' 2>/dev/null | grep -q 'is-default-class' || MISSING+=("default StorageClass (bootstrap/05)")
kubectl top nodes >/dev/null 2>&1 || MISSING+=("metrics-server (bootstrap/02)")
kubectl get ingressclass nginx >/dev/null 2>&1 || MISSING+=("ingress-nginx (bootstrap/03)")
kubectl get crd certificates.cert-manager.io >/dev/null 2>&1 || MISSING+=("cert-manager (bootstrap/07)")
kubectl get crd applications.argoproj.io >/dev/null 2>&1 || MISSING+=("Argo CD (bootstrap/06)")
kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1 || MISSING+=("kube-prometheus-stack (up.sh --stacks)")
kubectl get gatewayclass eg >/dev/null 2>&1 || MISSING+=("Envoy Gateway (bootstrap/11)")
[[ ${#MISSING[@]} -gt 0 ]] && log "WARN: нет аддонов: ${MISSING[*]}"

# 3) Прогон.
log "sweep (может занять час)"
SWEEP_LOG="$(mktemp)"
REPORT_FILE="$REPORT_DIR/$STAMP-sweep.md" bash "$ROOT_DIR/scripts/qa/sweep.sh" > "$SWEEP_LOG" 2>&1
SWEEP_RC=$?
TOTAL_LINE="$(grep -m1 '^TOTAL:' "$SWEEP_LOG" || echo 'TOTAL: ?')"
log "$TOTAL_LINE"

{
  echo "# Nightly QA $STAMP"
  echo
  echo "- сервер: $(kubectl version -o json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["serverVersion"]["gitVersion"])' 2>/dev/null || echo '?')"
  echo "- ноды не в Ready: $NOT_READY"
  [[ ${#MISSING[@]} -gt 0 ]] && echo "- ⚠️ отсутствуют аддоны: ${MISSING[*]}"
  echo "- результат: **$TOTAL_LINE** (sweep rc=$SWEEP_RC)"
  echo
  echo '```'
  grep -E '\| (PASS|FAIL)|FAIL' "$SWEEP_LOG" | head -60
  echo '```'
  echo
  echo "Полная таблица: \`$REPORT_DIR/$STAMP-sweep.md\`"
} > "$REPORT"
rm -f "$SWEEP_LOG"

log "отчёт: $REPORT"
exit "$SWEEP_RC"
