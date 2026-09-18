#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin kubectl
require_namespace lab

kubectl get crd clusters.postgresql.cnpg.io >/dev/null 2>&1 || fail "CRD clusters.postgresql.cnpg.io не найден — оператор CNPG не установлен (verify/prepare.sh)"
kubectl get crd scheduledbackups.postgresql.cnpg.io >/dev/null 2>&1 || fail "CRD scheduledbackups.postgresql.cnpg.io не найден"

kubectl -n lab wait --for=condition=Ready cluster/my-db --timeout=400s >/dev/null || fail "Cluster my-db не стал Ready за 400s"
PHASE=$(kubectl -n lab get cluster my-db -o jsonpath='{.status.phase}' 2>/dev/null || true)
[[ "$PHASE" == "Cluster in healthy state" ]] || fail "Cluster my-db: phase '$PHASE', ожидали 'Cluster in healthy state'"
require_deployment_ready lab db-client 120s
ok "Part 2: Cluster my-db healthy, db-client готов"

RW=$(kubectl -n lab get endpointslices -l kubernetes.io/service-name=my-db-rw -o jsonpath='{.items[*].endpoints[*].targetRef.name}' 2>/dev/null || true)
RO=$(kubectl -n lab get endpointslices -l kubernetes.io/service-name=my-db-ro -o jsonpath='{.items[*].endpoints[*].targetRef.name}' 2>/dev/null || true)
PRIMARY=$(kubectl -n lab get cluster my-db -o jsonpath='{.status.currentPrimary}' 2>/dev/null || true)
[[ -n "$PRIMARY" ]] || fail "status.currentPrimary пуст"
[[ "$RW" == "$PRIMARY" ]] || fail "my-db-rw должен вести только на primary ($PRIMARY), endpoints: '$RW'"
[[ -n "$RO" && "$RO" != *"$PRIMARY"* ]] || fail "my-db-ro не должен содержать primary ($PRIMARY), endpoints: '$RO'"
ok "Part 2: маршрутизация — rw -> $PRIMARY, ro -> $RO"

kubectl -n lab get scheduledbackup my-db-backup >/dev/null 2>&1 || fail "ScheduledBackup my-db-backup не найден"
ok "Part 4: ScheduledBackup my-db-backup существует"

OLD="$PRIMARY"
kubectl -n lab delete pod "$OLD" --wait=false >/dev/null
NEW=""
for _ in $(seq 1 60); do
  NEW=$(kubectl -n lab get cluster my-db -o jsonpath='{.status.currentPrimary}' 2>/dev/null || true)
  PHASE=$(kubectl -n lab get cluster my-db -o jsonpath='{.status.phase}' 2>/dev/null || true)
  [[ -n "$NEW" && "$NEW" != "$OLD" && "$PHASE" == "Cluster in healthy state" ]] && break
  sleep 5
done
[[ -n "$NEW" && "$NEW" != "$OLD" ]] || fail "failover: primary не сменился за 300s (был $OLD, сейчас '${NEW:-}', phase '${PHASE:-}')"
[[ "$PHASE" == "Cluster in healthy state" ]] || fail "failover: primary теперь $NEW, но кластер не вернулся в healthy за 300s (phase '$PHASE')"
ROLE=$(kubectl -n lab get pod "$OLD" -o jsonpath='{.metadata.labels.cnpg\.io/instanceRole}' 2>/dev/null || true)
[[ "$ROLE" == "replica" ]] || fail "старый primary $OLD должен вернуться репликой, метка cnpg.io/instanceRole: '${ROLE:-нет}'"
ok "Part 3: failover $OLD -> $NEW, старый primary вернулся репликой"

ok "module 21 verified"
