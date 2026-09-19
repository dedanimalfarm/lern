#!/usr/bin/env bash
# Прогон verify по всем модулям и проектам.
#
# Использование:
#   scripts/qa/sweep.sh                       # все модули + проекты
#   scripts/qa/sweep.sh modules/05-storage projects/project-a-platform-namespace
#   ONLY='^(0[1-9]|1[0-4]|20)-' scripts/qa/sweep.sh   # фильтр по имени (regex)
#   MODULE_TIMEOUT=900 REPORT_FILE=/tmp/qa.md scripts/qa/sweep.sh
set -u

export KUBECONFIG="${KUBECONFIG:-/root/.kube/kubespray.conf}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODULE_TIMEOUT="${MODULE_TIMEOUT:-600}"
REPORT_FILE="${REPORT_FILE:-/root/k8s-lab-handoff/qa-report.md}"
ONLY="${ONLY:-}"

PASS_COUNT=0
FAIL_COUNT=0
TOTAL_COUNT=0
FAILED=()

# Контракт стенда (ns lab + ResourceQuota/LimitRange) восстанавливаем ПЕРЕД
# КАЖДЫМ модулем. Причина: clean-module.sh в конце прогона сносит в lab вообще
# всё, включая quota и limitrange, а часть модулей на них рассчитывает (m12
# наоборот — снимает их в prepare и возвращает в cleanup). Без восстановления
# результат модуля зависел от того, что делал предыдущий: m12 «проходил» в
# июньском sweep, хотя под контрактом стенда его BestEffort-под невозможен.
restore_baseline() {
  bash "$ROOT_DIR/scripts/bootstrap/00-create-namespaces.sh" >/dev/null 2>&1 || true
  bash "$ROOT_DIR/scripts/bootstrap/01-apply-quotas.sh" >/dev/null 2>&1 || true
}

targets() {
  if [[ $# -gt 0 ]]; then
    printf '%s\n' "$@"
    return
  fi
  for d in "$ROOT_DIR"/modules/* "$ROOT_DIR"/projects/*; do
    [[ -d "$d/verify" ]] || continue
    local name; name="$(basename "$d")"
    # модули из ROADMAP, которых ещё нет (26/27) — пропускаем
    [[ "$name" =~ ^26-|^27- ]] && continue
    [[ -n "$ONLY" && ! "$name" =~ $ONLY ]] && continue
    echo "$(basename "$(dirname "$d")")/$name"
  done
}

mkdir -p "$(dirname "$REPORT_FILE")" 2>/dev/null || true
{
  echo "# QA Report — $(date '+%Y-%m-%d %H:%M %Z')"
  echo ""
  echo "kubeconfig: \`$KUBECONFIG\` · server: $(kubectl version -o json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["serverVersion"]["gitVersion"])' 2>/dev/null || echo '?')"
  echo ""
  echo "| Module/Project | Status | Notes |"
  echo "|----------------|--------|-------|"
} > "$REPORT_FILE"

printf "%-40s | %-10s\n" "MODULE/PROJECT" "STATUS"
echo "-----------------------------------------+-----------"

while read -r TARGET; do
  [[ -n "$TARGET" ]] || continue
  TOTAL_COUNT=$((TOTAL_COUNT+1))
  restore_baseline

  # timeout шлёт SIGTERM на дедлайне (trap в run-module.sh подчистит),
  # SIGKILL — спустя ещё 30с. Без него зависший модуль морозит весь sweep.
  LOG="$(mktemp)"
  if timeout --kill-after=30 "$MODULE_TIMEOUT" \
       bash "$ROOT_DIR/scripts/qa/run-module.sh" "$TARGET" > "$LOG" 2>&1; then
    printf "%-40s | \e[32mPASS\e[0m\n" "$TARGET"
    echo "| $TARGET | ✅ PASS | |" >> "$REPORT_FILE"
    PASS_COUNT=$((PASS_COUNT+1))
  else
    rc=$?
    note=""
    if [[ "$rc" == 124 || "$rc" == 137 ]]; then
      note="TIMEOUT ${MODULE_TIMEOUT}s"
    else
      # первая строка [FAIL]/Error — чтобы отчёт был полезен без чтения логов
      note="$(grep -m1 -E '^\[FAIL\]|^Error|error:' "$LOG" | cut -c1-160 | tr '|' '/')"
    fi
    printf "%-40s | \e[31mFAIL\e[0m %s\n" "$TARGET" "$note"
    echo "| $TARGET | ❌ FAIL | ${note:-см. лог} |" >> "$REPORT_FILE"
    FAIL_COUNT=$((FAIL_COUNT+1))
    FAILED+=("$TARGET")
  fi
  rm -f "$LOG"
done < <(targets "$@")

# Стенд после прогона остаётся с baseline-контрактом, а не пустым.
restore_baseline

echo "-----------------------------------------+-----------"
echo "TOTAL: $TOTAL_COUNT, PASS: $PASS_COUNT, FAIL: $FAIL_COUNT"
{
  echo ""
  echo "**TOTAL: $TOTAL_COUNT, PASS: $PASS_COUNT, FAIL: $FAIL_COUNT**"
  if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo ""
    echo "Повторить упавшее:"
    echo '```bash'
    echo "scripts/qa/sweep.sh ${FAILED[*]}"
    echo '```'
  fi
} >> "$REPORT_FILE"
echo "отчёт: $REPORT_FILE"

[[ $FAIL_COUNT -gt 0 ]] && exit 1
exit 0
