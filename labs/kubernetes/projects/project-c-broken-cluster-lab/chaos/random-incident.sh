#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS="${NS:-lab}"
STATE="${CHAOS_STATE:-/tmp/project-c-chaos.txt}"
CATALOG=(auth-service.yaml catalog-api.yaml payment-worker.yaml report-generator.yaml dns-failure.yaml scheduling-pending.yaml sync-fail.yaml cert-expiry)

usage() { echo "использование: $0 start [N] | reveal | reset"; exit 2; }

cmd_start() {
  local n="${1:-1}"
  [[ -f "$STATE" ]] && { echo "учение уже идёт: $(wc -l < "$STATE") инцидент(ов). Сначала: $0 reset"; exit 1; }
  local pool=("${CATALOG[@]}")
  kubectl get crd applications.argoproj.io >/dev/null 2>&1 || pool=("${pool[@]/sync-fail.yaml}")
  mapfile -t pick < <(printf '%s\n' "${pool[@]}" | grep -v '^$' | shuf -n "$n")
  for item in "${pick[@]}"; do
    if [[ "$item" == cert-expiry ]]; then
      bash "$DIR/broken/cert-expiry/setup.sh" "$NS" >/dev/null
    else
      kubectl apply -f "$DIR/broken/$item" >/dev/null
    fi
    echo "$item" >> "$STATE"
  done
  echo "применено инцидентов: ${#pick[@]} (ns $NS)"
  echo "симптомы:  kubectl -n $NS get pods,application -A 2>/dev/null | grep -vE 'Running|Completed|Synced'"
  echo "триаж:     bash $DIR/triage/incident-triage.sh $NS <label>"
  echo "ответ спрятан в $STATE — открывать только через: $0 reveal"
}

cmd_reveal() {
  [[ -f "$STATE" ]] || { echo "учение не запущено"; exit 1; }
  sed 's/^/  - /' "$STATE"
}

cmd_reset() {
  [[ -f "$STATE" ]] || { echo "учение не запущено"; exit 0; }
  while read -r item; do
    if [[ "$item" == cert-expiry ]]; then
      kubectl -n "$NS" delete secret web-tls --ignore-not-found >/dev/null
    else
      kubectl delete -f "$DIR/broken/$item" --ignore-not-found >/dev/null 2>&1 || true
    fi
  done < "$STATE"
  rm -f "$STATE"
  echo "инциденты убраны"
}

case "${1:-}" in
  start)  cmd_start "${2:-1}" ;;
  reveal) cmd_reveal ;;
  reset)  cmd_reset ;;
  *) usage ;;
esac
