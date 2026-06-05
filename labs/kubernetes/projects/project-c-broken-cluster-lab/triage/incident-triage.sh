#!/usr/bin/env bash
# incident-triage.sh — авто-классификатор инцидента по симптому пода.
# Использование: bash incident-triage.sh <namespace> <label-selector>
#   пример: bash incident-triage.sh lab app=report-generator
# Смотрит фазу/waiting/lastState/events/логи и печатает: диагноз + вероятную
# причину + ПЕРВУЮ команду. Синтез деревьев диагностики модулей 02/04/05/06/08.
set -uo pipefail
NS="${1:-lab}"
SEL="${2:-}"
[[ -z "$SEL" ]] && { echo "usage: $0 <namespace> <label-selector>  (напр. lab app=foo)"; exit 2; }

POD=$(kubectl -n "$NS" get pod -l "$SEL" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
[[ -z "$POD" ]] && { echo "поды по селектору '$SEL' в ns/$NS не найдены"; exit 2; }

phase=$(kubectl -n "$NS" get pod "$POD" -o jsonpath='{.status.phase}' 2>/dev/null)
ready=$(kubectl -n "$NS" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
wreason=$(kubectl -n "$NS" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null)
lreason=$(kubectl -n "$NS" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}' 2>/dev/null)
lexit=$(kubectl -n "$NS" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].lastState.terminated.exitCode}' 2>/dev/null)

echo "== Триаж: ns/$NS pod/$POD =="
echo "   phase=$phase ready=${ready:-?} waiting=${wreason:-none} lastState=${lreason:-none}(exit ${lexit:-?})"
echo

diag(){ printf 'ДИАГНОЗ:   %s\n' "$1"; }
cause(){ printf 'ПРИЧИНА:   %s\n' "$1"; }
first(){ printf 'ПЕРВАЯ КОМАНДА: %s\n' "$1"; }

# 1) Pending — не размещён.
if [[ "$phase" == "Pending" ]]; then
  ev=$(kubectl -n "$NS" describe pod "$POD" 2>/dev/null | grep -m1 -iE 'FailedScheduling|Insufficient|taint|unbound|PersistentVolumeClaim' || true)
  diag "Pending — scheduler не разместил под"
  if echo "$ev" | grep -qi 'Insufficient'; then
    cause "не хватает ресурсов на нодах (requests > свободного). Модуль 06/12."
  elif echo "$ev" | grep -qi 'taint'; then
    cause "нода под taint, нет toleration. Модуль 06/13."
  elif echo "$ev" | grep -qi 'PersistentVolumeClaim\|unbound'; then
    cause "PVC не Bound / нет StorageClass. Модуль 05."
  else
    cause "см. Events (nodeSelector/affinity/quota)."
  fi
  first "kubectl -n $NS describe pod $POD | grep -A3 Events"
  echo "   ($ev)"; exit 0
fi

# 2) Waiting reason — образ или crashloop.
case "$wreason" in
  ImagePullBackOff|ErrImagePull)
    diag "образ не тянется ($wreason)"
    cause "неверный тег/реестр/нет imagePullSecret. Модуль 01/03."
    first "kubectl -n $NS describe pod $POD | grep -A2 -i 'failed to pull'"; exit 0 ;;
  CrashLoopBackOff)
    if [[ "$lreason" == "OOMKilled" ]]; then
      diag "CrashLoop из-за OOMKilled (exit 137)"
      cause "контейнер превышает limits.memory. Модуль 02/12."
      first "kubectl -n $NS get pod $POD -o jsonpath='{.status.containerStatuses[0].lastState.terminated}'"; exit 0
    fi
    diag "CrashLoopBackOff (exit ${lexit:-?})"
    cause "приложение падает на старте (баг/конфиг) или строгая liveness. Модуль 02/08."
    first "kubectl -n $NS logs $POD --previous --tail=20"; exit 0 ;;
  CreateContainerConfigError)
    diag "CreateContainerConfigError"
    cause "нет ConfigMap/Secret или невалидный securityContext. Модуль 07."
    first "kubectl -n $NS describe pod $POD | grep -A3 Events"; exit 0 ;;
esac

# 3) Running, но не Ready — readiness.
if [[ "$phase" == "Running" && "$ready" != "true" ]]; then
  diag "Running, но НЕ Ready (0/1)"
  cause "readinessProbe фейлится (путь/порт/тайминг) — под вне Endpoints. Модуль 02."
  first "kubectl -n $NS describe pod $POD | grep -A2 'Readiness probe failed'"; exit 0
fi

# 4) Running + Ready — но, может, DNS/сетевой сбой виден в логах.
if [[ "$phase" == "Running" && "$ready" == "true" ]]; then
  if kubectl -n "$NS" logs "$POD" --tail=20 2>/dev/null | grep -qiE 'bad address|could not resolve|RESOLVE_FAIL|connection timed out|no servers'; then
    diag "под Running, но в логах ошибки РЕЗОЛВА/сети"
    cause "DNS/egress закрыт NetworkPolicy (нет allow-dns) или CoreDNS недоступен. Модуль 04/15."
    first "kubectl -n $NS get netpol; kubectl -n $NS exec $POD -- nslookup kubernetes.default"; exit 0
  fi
  diag "под Running и Ready — на уровне пода инцидента НЕ видно"
  cause "проблема может быть в Service/Ingress/NetworkPolicy/внешней зависимости."
  first "kubectl -n $NS get endpoints,netpol; kubectl -n $NS logs $POD --tail=30"; exit 0
fi

diag "нераспознанное состояние (phase=$phase)"
first "kubectl -n $NS describe pod $POD"
