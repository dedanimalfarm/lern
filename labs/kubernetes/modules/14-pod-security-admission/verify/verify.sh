#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin kubectl
require_namespace lab-restricted

# namespace должен ПРИНУДИТЕЛЬНО применять restricted.
# go-template + index с КАВЫЧКАМИ-ключом портабельнее jsonpath: ключ метки содержит
# точки (pod-security.kubernetes.io/enforce), а экранирование `\.` в jsonpath-пути
# ведёт себя по-разному между версиями kubectl/шеллами. index трактует ключ как
# строковый литерал — без экранирования. Отсутствует метка -> "<no value>" (тоже != restricted).
ENF=$(kubectl get ns lab-restricted -o go-template='{{index .metadata.labels "pod-security.kubernetes.io/enforce"}}' 2>/dev/null || true)
[[ "$ENF" == "restricted" ]] || fail "lab-restricted enforce='$ENF', expected 'restricted'"

# соответствующий под должен быть запущен
require_pod_phase lab-restricted app=good Running

# ValidatingAdmissionPolicy установлена
kubectl get validatingadmissionpolicy no-latest-tag >/dev/null 2>&1 \
  || fail "ValidatingAdmissionPolicy no-latest-tag not found"
ok "PSA restricted enforced + good-pod Running + VAP no-latest present"

ok "module 14 verified"
