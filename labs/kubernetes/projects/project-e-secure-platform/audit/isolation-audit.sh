#!/usr/bin/env bash
# isolation-audit.sh — аудит ИЗОЛЯЦИИ тенанта на multi-tenant платформе.
# Использование: bash isolation-audit.sh [tenant-namespace]   (default: tenant-a)
# Печатает [PASS]/[FAIL] по 6 контролям изоляции; код возврата !=0 при провале.
# Переиспользуемо для любого namespace-тенанта — это «гейт» безопасности платформы.
set -uo pipefail
NS="${1:-tenant-a}"
command -v kubectl >/dev/null || { echo "нужен kubectl"; exit 2; }
kubectl get ns "$NS" >/dev/null 2>&1 || { echo "namespace $NS не найден"; exit 2; }
SA="${NS}-deployer"          # соглашение об имени SA тенанта
fails=0
pass(){ printf '  [PASS] %s\n' "$1"; }
fail(){ printf '  [FAIL] %s\n' "$1"; fails=$((fails+1)); }
chk(){ [[ "$1" == "true" ]] && pass "$2" || fail "$2"; }

echo "== Аудит изоляции тенанта: $NS =="

# 1. PSA: namespace помечен enforce=restricted.
psa=$(kubectl get ns "$NS" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null)
chk "$([[ "$psa" == "restricted" ]] && echo true || echo false)" "PSA enforce=restricted (got: ${psa:-none})"

# 2. default-deny NetworkPolicy (пустой podSelector + оба policyTypes).
chk "$(kubectl -n "$NS" get netpol -o json | jq -e '.items[]|select((.spec.podSelector.matchLabels|length // 0)==0 and (.spec.policyTypes|index("Ingress")) and (.spec.policyTypes|index("Egress")))' >/dev/null 2>&1 && echo true || echo false)" "default-deny NetworkPolicy (Ingress+Egress)"

# 3. allow-dns NetworkPolicy (иначе под не резолвит на Kubespray).
chk "$(kubectl -n "$NS" get netpol allow-dns >/dev/null 2>&1 && echo true || echo false)" "allow-dns NetworkPolicy присутствует"

# 4. ResourceQuota + LimitRange (лимиты namespace).
chk "$([[ -n "$(kubectl -n "$NS" get resourcequota -o name 2>/dev/null)" && -n "$(kubectl -n "$NS" get limitrange -o name 2>/dev/null)" ]] && echo true || echo false)" "ResourceQuota + LimitRange заданы"

# 5. RBAC-изоляция: SA тенанта МОЖЕТ в своём ns, НЕ может в чужом (tenant-b/default).
other="tenant-b"; [[ "$NS" == "tenant-b" ]] && other="tenant-a"
can_own=$(kubectl auth can-i list pods -n "$NS" --as="system:serviceaccount:${NS}:${SA}" 2>/dev/null)
can_other=$(kubectl auth can-i list pods -n "$other" --as="system:serviceaccount:${NS}:${SA}" 2>/dev/null)
chk "$([[ "$can_own" == "yes" && "$can_other" == "no" ]] && echo true || echo false)" "RBAC: SA видит свой ns ($can_own), не чужой $other ($can_other)"

# 6. policy-as-code: VAP-биндинг нацелен на платформенные namespaces.
chk "$(kubectl get validatingadmissionpolicybinding tenant-no-latest-tag-binding >/dev/null 2>&1 && echo true || echo false)" "VAP no-latest-tag binding активен"

echo
if [[ "$fails" -eq 0 ]]; then
  echo "ИТОГ: все контроли изоляции на месте для $NS"
else
  echo "ИТОГ: провалов — $fails (см. [FAIL] выше)"
fi
exit "$fails"
