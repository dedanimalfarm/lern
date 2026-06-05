#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

PASS_COUNT=0
FAIL_COUNT=0
TOTAL_COUNT=0

REPORT_FILE="/root/k8s-lab-handoff/qa-report.md"
echo "# Baseline QA Report" > "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "| Module/Project | Status | Notes |" >> "$REPORT_FILE"
echo "|----------------|--------|-------|" >> "$REPORT_FILE"

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
  if [[ "$BASENAME" =~ ^18-|^21-|^23-|^24-|^26-|^27- ]]; then
    continue
  fi

  TOTAL_COUNT=$((TOTAL_COUNT+1))
  
  # Run module and capture output
  OUTPUT=$(bash "$ROOT_DIR/scripts/qa/run-module.sh" "$TARGET" 2>&1)
  if [[ $? -eq 0 ]]; then
    printf "%-40s | \e[32mPASS\e[0m\n" "$TARGET"
    echo "| $TARGET | ✅ PASS | |" >> "$REPORT_FILE"
    PASS_COUNT=$((PASS_COUNT+1))
  else
    printf "%-40s | \e[31mFAIL\e[0m\n" "$TARGET"
    echo "| $TARGET | ❌ FAIL | |" >> "$REPORT_FILE"
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
