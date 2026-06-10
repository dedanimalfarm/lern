#!/usr/bin/env bash
set -u

export KUBECONFIG="${KUBECONFIG:-/root/.kube/kubespray.conf}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

PASS_COUNT=0
FAIL_COUNT=0
TOTAL_COUNT=0

REPORT_FILE="/root/k8s-lab-handoff/qa-report.md"
{
  echo "# Baseline QA Report"
  echo ""
  echo "| Module/Project | Status | Notes |"
  echo "|----------------|--------|-------|"
} > "$REPORT_FILE"

printf "%-40s | %-10s\n" "MODULE/PROJECT" "STATUS"
echo "-----------------------------------------+-----------"

for d in "$ROOT_DIR"/modules/* "$ROOT_DIR"/projects/*; do
  [[ -d "$d" ]] || continue
  BASENAME="$(basename "$d")"
  PARENT="$(basename "$(dirname "$d")")"
  TARGET="$PARENT/$BASENAME"
  
  if [[ ! -d "$d/verify" ]]; then
    continue
  fi

  # Skip optional / not implemented modules
  if [[ "$BASENAME" =~ ^26-|^27- ]]; then
    continue
  fi

  TOTAL_COUNT=$((TOTAL_COUNT+1))
  
  # Run module под жёстким per-module таймаутом. Без него зависший модуль
  # (напр. Argo-приложение, которое никогда не станет Synced) морозит ВЕСЬ sweep
  # на часы. timeout шлёт SIGTERM на дедлайне (trap в run-module.sh подчистит),
  # SIGKILL — спустя ещё 30с, если не вышел. 600с с запасом покрывают самые
  # медленные модули (CNPG/Loki/Argo).
  MODULE_TIMEOUT="${MODULE_TIMEOUT:-600}"
  if timeout --kill-after=30 "$MODULE_TIMEOUT" \
       bash "$ROOT_DIR/scripts/qa/run-module.sh" "$TARGET" > /dev/null 2>&1; then
    printf "%-40s | \e[32mPASS\e[0m\n" "$TARGET"
    echo "| $TARGET | ✅ PASS | |" >> "$REPORT_FILE"
    PASS_COUNT=$((PASS_COUNT+1))
  else
    rc=$?
    note=""; [[ "$rc" == 124 || "$rc" == 137 ]] && note=" (TIMEOUT ${MODULE_TIMEOUT}s)"
    printf "%-40s | \e[31mFAIL%s\e[0m\n" "$TARGET" "$note"
    echo "| $TARGET | ❌ FAIL |$note |" >> "$REPORT_FILE"
    FAIL_COUNT=$((FAIL_COUNT+1))
  fi
done

echo "-----------------------------------------+-----------"
echo "TOTAL: $TOTAL_COUNT, PASS: $PASS_COUNT, FAIL: $FAIL_COUNT"
echo "" >> "$REPORT_FILE"
echo "**TOTAL: $TOTAL_COUNT, PASS: $PASS_COUNT, FAIL: $FAIL_COUNT**" >> "$REPORT_FILE"

if [[ $FAIL_COUNT -gt 0 ]]; then
  exit 1
fi
exit 0
