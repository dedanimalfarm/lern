#!/usr/bin/env bash
# run-all-memory.sh: Run verify -> cleanup for all memory management labs.
set -uo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "запусти как root: sudo ./run-all-memory.sh" >&2
  exit 1
fi

MEM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$MEM_DIR" || exit 1

C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_RESET=$'\033[0m'

LABS=(
  "lab01"
  "lab02"
  "lab03"
)

OK=()
FAIL=()

for lab in "${LABS[@]}"; do
  echo "############################################################"
  echo "##  LAB: $lab"
  echo "############################################################"
  
  # Ensure we clean up any previous failures first
  if [[ -f "$lab/cleanup.sh" ]]; then
    (cd "$lab" && chmod +x *.sh 2>/dev/null || true)
    (cd "$lab" && ./cleanup.sh >/dev/null 2>&1 || true)
  fi

  # Run Verify
  STATUS=0
  echo "Running verification..."
  if [[ -f "$lab/verify.sh" ]]; then
    (cd "$lab" && chmod +x verify.sh 2>/dev/null || true)
    (cd "$lab" && ./verify.sh) || STATUS=1
  else
    echo "verify.sh not found!"
    STATUS=1
  fi

  # Run Cleanup
  echo "Running cleanup..."
  if [[ -f "$lab/cleanup.sh" ]]; then
    (cd "$lab" && ./cleanup.sh) || true
  fi

  if [[ $STATUS -eq 0 ]]; then
    echo "Result: PASS"
    OK+=("$lab")
  else
    echo "Result: FAIL"
    FAIL+=("$lab")
  fi
  echo ""
done

echo "============================================================"
echo "MEMORY LABS SUMMARY:"
echo "============================================================"
for l in "${OK[@]}";   do printf "  %s✓ PASS%s   %s\n" "$C_GREEN" "$C_RESET" "$l"; done
for l in "${FAIL[@]}"; do printf "  %s✗ FAIL%s   %s\n" "$C_RED"   "$C_RESET" "$l"; done

echo
echo "PASS: ${#OK[@]}  FAIL: ${#FAIL[@]}"
[[ ${#FAIL[@]} -eq 0 ]]
