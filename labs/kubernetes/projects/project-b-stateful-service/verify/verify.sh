#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin kubectl
require_namespace lab
require_resource lab sts redis
require_resource lab svc redis-headless
require_resource lab cronjob redis-backup
require_resource lab pdb redis-pdb

kubectl -n lab rollout status sts/redis --timeout=300s >/dev/null || fail "StatefulSet redis не вышел на 3/3 Ready за 300s"
for i in 0 1 2; do
  PH=$(kubectl -n lab get pvc "data-redis-$i" -o jsonpath='{.status.phase}' 2>/dev/null || true)
  [[ "$PH" == "Bound" ]] || fail "PVC data-redis-$i не Bound (phase: '${PH:-нет}')"
done
ok "StatefulSet redis 3/3 Ready, PVC каждой реплики Bound"

CIP=$(kubectl -n lab get svc redis-headless -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)
[[ "$CIP" == "None" ]] || fail "redis-headless должен быть headless (clusterIP: None), сейчас '$CIP'"
RO=$(kubectl -n lab get sts redis -o jsonpath='{.spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem}' 2>/dev/null || true)
NR=$(kubectl -n lab get sts redis -o jsonpath='{.spec.template.spec.securityContext.runAsNonRoot}' 2>/dev/null || true)
[[ "$RO" == "true" && "$NR" == "true" ]] || fail "hardening: ожидали readOnlyRootFilesystem=true и runAsNonRoot=true (сейчас $RO / $NR)"
ok "headless Service и hardened securityContext на месте"

kubectl -n lab delete pod verify-redis --ignore-not-found --force --grace-period=0 >/dev/null 2>&1 || true
PONG=$(kubectl -n lab run verify-redis --rm -i --restart=Never --quiet --image=redis:7.2-alpine -- \
  redis-cli -h redis-1.redis-headless.lab.svc.cluster.local PING 2>/dev/null || true)
[[ "$PONG" == *PONG* ]] || fail "redis-1.redis-headless не отвечает PONG через headless DNS (получили: '${PONG:-пусто}')"
ok "DNS-идентичность: redis-1.redis-headless -> PONG"

kubectl -n lab delete job verify-backup --ignore-not-found >/dev/null 2>&1 || true
kubectl -n lab create job --from=cronjob/redis-backup verify-backup >/dev/null || fail "не удалось создать Job из CronJob redis-backup"
kubectl -n lab wait --for=condition=complete job/verify-backup --timeout=180s >/dev/null || fail "бэкап-Job не завершился за 180s: $(kubectl -n lab logs job/verify-backup 2>/dev/null | tail -3 || true)"
kubectl -n lab logs job/verify-backup 2>/dev/null | grep -q '/backup/redis-.*\.rdb' || fail "в логах бэкапа нет записанного /backup/redis-*.rdb"
kubectl -n lab delete job verify-backup --ignore-not-found >/dev/null 2>&1 || true
ok "бэкап: Job из CronJob записал RDB на redis-backup-pvc"

if [ -x "$(dirname "$0")/../audit/stateful-audit.sh" ]; then
  "$(dirname "$0")/../audit/stateful-audit.sh" || fail "audit-скрипт нашёл нарушения"
fi

ok "project-b verified"
