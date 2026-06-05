#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin kubectl
require_namespace lab

# Часть 1: параллельный Job завершился ПОЛНОСТЬЮ (condition Complete = все completions).
require_resource lab job job-parallel
kubectl -n lab wait --for=condition=complete job/job-parallel --timeout=180s >/dev/null 2>&1 \
  || fail "job-parallel did not reach condition=complete within 180s"
SUCC=$(kubectl -n lab get job job-parallel -o jsonpath='{.status.succeeded}' 2>/dev/null || echo 0)
WANT=$(kubectl -n lab get job job-parallel -o jsonpath='{.spec.completions}' 2>/dev/null || echo 0)
[[ "$SUCC" == "$WANT" && "$WANT" -ge 1 ]] || fail "job-parallel succeeded=$SUCC, expected $WANT"
ok "job-parallel completed all $WANT completions"

# Часть 2: Indexed Job завершился и реально работал в режиме Indexed по индексам 0-3.
require_resource lab job job-indexed
kubectl -n lab wait --for=condition=complete job/job-indexed --timeout=180s >/dev/null 2>&1 \
  || fail "job-indexed did not reach condition=complete within 180s"
MODE=$(kubectl -n lab get job job-indexed -o jsonpath='{.spec.completionMode}' 2>/dev/null || true)
[[ "$MODE" == "Indexed" ]] || fail "job-indexed completionMode='$MODE', expected 'Indexed'"
IDX=$(kubectl -n lab get job job-indexed -o jsonpath='{.status.completedIndexes}' 2>/dev/null || true)
[[ "$IDX" == "0-3" ]] || fail "job-indexed completedIndexes='$IDX', expected '0-3'"
ok "job-indexed Indexed mode, completedIndexes=$IDX"

# Часть 4: CronJob создан с расписанием.
require_resource lab cronjob batch-report
SCHED=$(kubectl -n lab get cronjob batch-report -o jsonpath='{.spec.schedule}' 2>/dev/null || true)
[[ -n "$SCHED" ]] || fail "cronjob/batch-report has no schedule"
ok "cronjob/batch-report present (schedule: $SCHED)"

ok "module 20 verified"
