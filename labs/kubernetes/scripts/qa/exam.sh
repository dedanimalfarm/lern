#!/usr/bin/env bash
# Экзамен-режим курса: случайные поломки из broken-сценариев любых модулей,
# без подсказки, какой модуль сломан, с таймером и подсчётом результата.
#
#   scripts/qa/exam.sh start [N]   # развернуть N инцидентов (по умолчанию 3)
#   scripts/qa/exam.sh status      # сколько прошло времени, что уже починено
#   scripts/qa/exam.sh check       # прогнать verify по задействованным модулям
#   scripts/qa/exam.sh reveal      # показать, что было сломано (после сдачи)
#   scripts/qa/exam.sh reset       # убрать всё за собой
#
# Переменные: POOL (regex по имени модуля), TIME_LIMIT (минут, по умолчанию 45),
#             STATE (файл состояния), KUBECONFIG.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE="${STATE:-/tmp/k8s-exam-state}"
TIME_LIMIT="${TIME_LIMIT:-45}"
export KUBECONFIG="${KUBECONFIG:-/root/.kube/kubespray.conf}"

# Пул по умолчанию — модули, которым хватает стенда без тяжёлых аддонов; их
# verify служит критерием «починено». Расширить: POOL='.' scripts/qa/exam.sh start
POOL="${POOL:-^(0[1-8]|1[0-4]|20)-}"

die() { echo "$*" >&2; exit 1; }
have_state() { [[ -s "$STATE" ]]; }

apply_scenario() {   # <module> <scenario-dir>
  local mod="$1" dir="$2"
  local mdir="$ROOT_DIR/modules/$mod"
  [[ -f "$mdir/verify/prepare.sh" ]] && bash "$mdir/verify/prepare.sh" >/dev/null 2>&1
  if [[ -f "$mdir/manifests/kustomization.yaml" ]]; then
    kubectl -n lab apply -k "$mdir/manifests" >/dev/null 2>&1
  elif [[ -d "$mdir/manifests" ]]; then
    kubectl -n lab apply -f "$mdir/manifests" -R >/dev/null 2>&1
  fi
  if [[ -f "$dir/setup.sh" ]]; then
    (cd "$mdir" && bash "$dir/setup.sh" >/dev/null 2>&1)
  elif [[ -f "$dir/kustomization.yaml" ]]; then
    kubectl -n lab apply -k "$dir" >/dev/null 2>&1
  else
    kubectl -n lab apply -f "$dir" >/dev/null 2>&1
  fi
}

cmd_start() {
  have_state && die "экзамен уже идёт ($(wc -l < "$STATE") инцидент(ов)). Сначала: $0 reset"
  local n="${1:-3}"
  kubectl --request-timeout=10s get nodes >/dev/null 2>&1 || die "кластер недоступен"

  mapfile -t pool < <(
    for d in "$ROOT_DIR"/modules/*/broken/scenario-*/; do
      local mod; mod="$(basename "$(dirname "$(dirname "$d")")")"
      [[ "$mod" =~ $POOL ]] || continue
      [[ -f "$ROOT_DIR/modules/$mod/verify/verify.sh" ]] || continue
      echo "$mod|$d"
    done
  )
  [[ ${#pool[@]} -ge $n ]] || die "в пуле всего ${#pool[@]} сценариев (POOL='$POOL')"

  echo "готовлю стенд и ломаю $n мест(а)…"
  bash "$ROOT_DIR/scripts/bootstrap/00-create-namespaces.sh" >/dev/null 2>&1
  bash "$ROOT_DIR/scripts/bootstrap/01-apply-quotas.sh" >/dev/null 2>&1

  : > "$STATE"
  date +%s > "${STATE}.started"
  # по одному сценарию на модуль, чтобы verify каждого модуля был однозначным
  local picked=() seen=""
  while IFS= read -r line; do
    local mod="${line%%|*}"
    [[ " $seen " == *" $mod "* ]] && continue
    seen="$seen $mod"
    picked+=("$line")
    [[ ${#picked[@]} -eq $n ]] && break
  done < <(printf '%s\n' "${pool[@]}" | shuf)

  for line in "${picked[@]}"; do
    local mod="${line%%|*}" dir="${line#*|}"
    apply_scenario "$mod" "$dir"
    echo "$mod|$dir" >> "$STATE"
  done

  cat <<EOF

=== ЭКЗАМЕН НАЧАТ ===
инцидентов: $n · лимит времени: ${TIME_LIMIT} мин · namespace: lab (и связанные)

Что делать: найти и починить всё сломанное. Какие модули задействованы — не
подсказывается. Смотрите симптомы так же, как в проде:

  kubectl -n lab get pods,deploy,svc,pvc
  kubectl -n lab get events --sort-by=.lastTimestamp | tail -20
  bash projects/project-c-broken-cluster-lab/triage/incident-triage.sh lab <label>

Проверить себя:   $0 check
Сдаться:          $0 reveal
Убрать за собой:  $0 reset
EOF
}

elapsed_min() {
  local started; started="$(cat "${STATE}.started" 2>/dev/null || echo 0)"
  echo $(( ( $(date +%s) - started ) / 60 ))
}

cmd_check() {
  have_state || die "экзамен не запущен"
  local passed=0 total=0
  echo "прогоняю verify по задействованным модулям (это займёт минуту)…"
  while IFS='|' read -r mod _; do
    total=$((total + 1))
    if timeout 300 bash "$ROOT_DIR/modules/$mod/verify/verify.sh" >/dev/null 2>&1; then
      printf "  \e[32m[OK]\e[0m   инцидент %d — починен\n" "$total"
      passed=$((passed + 1))
    else
      printf "  \e[31m[FAIL]\e[0m инцидент %d — ещё нет\n" "$total"
    fi
  done < "$STATE"
  local mins; mins="$(elapsed_min)"
  echo "---"
  echo "результат: $passed из $total · прошло $mins мин из $TIME_LIMIT"
  if [[ "$passed" -eq "$total" ]]; then
    if [[ "$mins" -le "$TIME_LIMIT" ]]; then
      echo -e "\e[32mСДАНО\e[0m — уложились в лимит."
    else
      echo -e "\e[33mВсё починено, но лимит превышен\e[0m (${mins} > ${TIME_LIMIT} мин)."
    fi
    echo "Разбор: $0 reveal · уборка: $0 reset"
  fi
}

cmd_status() {
  have_state || die "экзамен не запущен"
  echo "инцидентов: $(wc -l < "$STATE") · прошло: $(elapsed_min) мин из $TIME_LIMIT"
  kubectl -n lab get pods 2>/dev/null | head -20
}

cmd_reveal() {
  have_state || die "экзамен не запущен"
  echo "было сломано:"
  while IFS='|' read -r mod dir; do
    local rel="${dir#"$ROOT_DIR"/}"
    echo "  - модуль $mod, ${rel%/}"
    echo "    разбор: ${rel}README.md"
  done < "$STATE"
}

cmd_reset() {
  if have_state; then
    while IFS='|' read -r mod _; do
      bash "$ROOT_DIR/scripts/clean/clean-module.sh" "modules/$mod" >/dev/null 2>&1
    done < "$STATE"
  fi
  for n in $(kubectl get nodes -o jsonpath='{range .items[?(@.spec.unschedulable==true)]}{.metadata.name}{"\n"}{end}' 2>/dev/null); do
    kubectl uncordon "$n" >/dev/null 2>&1
  done
  bash "$ROOT_DIR/scripts/bootstrap/00-create-namespaces.sh" >/dev/null 2>&1
  bash "$ROOT_DIR/scripts/bootstrap/01-apply-quotas.sh" >/dev/null 2>&1
  rm -f "$STATE" "${STATE}.started"
  echo "убрано, стенд вернулся к baseline"
}

case "${1:-}" in
  start)  shift; cmd_start "$@" ;;
  check)  cmd_check ;;
  status) cmd_status ;;
  reveal) cmd_reveal ;;
  reset)  cmd_reset ;;
  *) echo "использование: $0 start [N] | status | check | reveal | reset" >&2; exit 2 ;;
esac
