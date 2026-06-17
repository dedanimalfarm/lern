#!/usr/bin/env bash
# run-all-docker.sh: Run cleanup -> verify -> cleanup for all Docker labs.
set -uo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "запусти как root: sudo ./run-all-docker.sh" >&2
  exit 1
fi

DOCKER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DOCKER_DIR" || exit 1

C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_RESET=$'\033[0m'

LABS=(
  "00-overview"
  "01-basics-cli"
  "02-images-dockerfile"
  "03-compose"
  "04-storage"
  "05-networking"
  "06-debug-troubleshooting"
  "07-security"
  "08-build-advanced"
  "09-registry-release"
  "10-operations-observability"
  "11-production-patterns"
  "12-capstone-projects"
  "13-cicd-github-actions"
  "14-docker-init-devcontainers"
  "15-dind-testcontainers"
  "16-docker-to-kubernetes"
)

OK=()
FAIL=()

for lab in "${LABS[@]}"; do
  echo "############################################################"
  echo "##  LAB: $lab"
  echo "############################################################"
  
  # Ensure we clean up any previous failures first
  if [[ -f "$lab/cleanup.sh" ]]; then
    echo "Running initial cleanup..."
    (cd "$lab" && chmod +x *.sh 2>/dev/null || true; ./cleanup.sh >/dev/null 2>&1 || true)
  fi

  STATUS=0
  if [[ -f "$lab/checks/verify.sh" ]]; then
    echo "Running verification..."
    (cd "$lab" && chmod +x checks/verify.sh 2>/dev/null || true; ./checks/verify.sh) || STATUS=1
  else
    echo "No verify.sh found!"
    STATUS=1
  fi

  # Run Cleanup
  if [[ -f "$lab/cleanup.sh" ]]; then
    echo "Running final cleanup..."
    (cd "$lab" && ./cleanup.sh >/dev/null 2>&1 || true)
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
echo "DOCKER LABS SUMMARY:"
echo "============================================================"
for l in "${OK[@]}";   do printf "  %s✓ PASS%s   %s\n" "$C_GREEN" "$C_RESET" "$l"; done
for l in "${FAIL[@]}"; do printf "  %s✗ FAIL%s   %s\n" "$C_RED"   "$C_RESET" "$l"; done

echo
echo "PASS: ${#OK[@]}  FAIL: ${#FAIL[@]}"
[[ ${#FAIL[@]} -eq 0 ]]
