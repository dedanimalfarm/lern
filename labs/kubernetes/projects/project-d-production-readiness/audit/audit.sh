#!/usr/bin/env bash
# audit.sh — аудит Deployment на ПРОД-ГОТОВНОСТЬ по чек-листу.
# Использование: bash audit.sh [namespace] [deployment]   (default: lab shop)
# Печатает [PASS]/[FAIL] по каждому критерию; код возврата !=0, если есть провал.
# Переиспользуемо для ЛЮБОГО приложения — это «гейт» прод-готовности.
set -uo pipefail
NS="${1:-lab}"; DEP="${2:-shop}"
command -v jq >/dev/null || { echo "нужен jq"; exit 2; }

J=$(kubectl -n "$NS" get deploy "$DEP" -o json 2>/dev/null) || { echo "Deployment $NS/$DEP не найден"; exit 2; }
APP=$(jq -r '.spec.selector.matchLabels.app // .metadata.name' <<<"$J")
fails=0
pass(){ printf '  [PASS] %s\n' "$1"; }
fail(){ printf '  [FAIL] %s\n' "$1"; fails=$((fails+1)); }
chk(){ local ok="$1" msg="$2"; [[ "$ok" == "true" ]] && pass "$msg" || fail "$msg"; }

c=$(jq '.spec.template.spec.containers[0]' <<<"$J")

echo "== Аудит прод-готовности: $NS/$DEP (app=$APP) =="

# 1. Доступность: >=2 реплик
chk "$([[ "$(jq -r '.spec.replicas' <<<"$J")" -ge 2 ]] && echo true || echo false)" "replicas >= 2 (переживает потерю пода)"

# 2. PodDisruptionBudget на этот app
chk "$(kubectl -n "$NS" get pdb -o json | jq --arg a "$APP" -e '.items[]|select(.spec.selector.matchLabels.app==$a)' >/dev/null 2>&1 && echo true || echo false)" "PodDisruptionBudget существует"

# 3. Распределение по нодам (topologySpread или podAntiAffinity)
chk "$(jq -e '(.spec.template.spec.topologySpreadConstraints!=null) or (.spec.template.spec.affinity.podAntiAffinity!=null)' <<<"$J" >/dev/null 2>&1 && echo true || echo false)" "topologySpread/podAntiAffinity (реплики на разные ноды)"

# 4. Probes: readiness + liveness
chk "$(jq -e '.readinessProbe!=null and .livenessProbe!=null' <<<"$c" >/dev/null 2>&1 && echo true || echo false)" "readinessProbe + livenessProbe заданы"

# 5. requests И limits (не BestEffort)
chk "$(jq -e '.resources.requests!=null and .resources.limits!=null' <<<"$c" >/dev/null 2>&1 && echo true || echo false)" "requests и limits заданы (не BestEffort)"

# 6. securityContext hardening
chk "$(jq -e '.securityContext.runAsNonRoot==true and .securityContext.allowPrivilegeEscalation==false and .securityContext.readOnlyRootFilesystem==true and (.securityContext.capabilities.drop|index("ALL")) and (.securityContext.seccompProfile.type!=null)' <<<"$c" >/dev/null 2>&1 && echo true || echo false)" "securityContext: nonRoot+noPrivEsc+ROfs+drop ALL+seccomp"

# 7. Образ запиннен (не :latest, не без тега)
img=$(jq -r '.image' <<<"$c")
chk "$([[ "$img" == *:* && "$img" != *:latest ]] && echo true || echo false)" "образ запиннен ($img)"

# 8. HPA на deployment
chk "$(kubectl -n "$NS" get hpa -o json | jq --arg d "$DEP" -e '.items[]|select(.spec.scaleTargetRef.name==$d)' >/dev/null 2>&1 && echo true || echo false)" "HorizontalPodAutoscaler настроен"

# 9. NetworkPolicy в namespace (есть default-deny)
chk "$(kubectl -n "$NS" get netpol -o json | jq -e '.items[]|select((.spec.podSelector.matchLabels|length)==0 and (.spec.policyTypes|index("Ingress")))' >/dev/null 2>&1 && echo true || echo false)" "default-deny NetworkPolicy в namespace"

# 10. Секреты НЕ в открытом env (только через secretKeyRef)
chk "$(jq -e '[.env[]?|select(.value!=null and (.name|test("(?i)(pass|secret|token|key)")))]|length==0' <<<"$c" >/dev/null 2>&1 && echo true || echo false)" "нет секретов в открытом env (только secretKeyRef)"

# 11. Observability: ServiceMonitor на app
chk "$(kubectl -n "$NS" get servicemonitor -o json 2>/dev/null | jq --arg a "$APP" -e '.items[]|select(.spec.selector.matchLabels.app==$a)' >/dev/null 2>&1 && echo true || echo false)" "ServiceMonitor (метрики собираются)"

echo "== Итог: провалов $fails из 11 =="
[[ "$fails" -eq 0 ]] && echo "ПРОД-ГОТОВО ✅" || echo "НЕ прод-готово ❌ ($fails критериев не выполнено)"
exit $(( fails > 0 ? 1 : 0 ))
