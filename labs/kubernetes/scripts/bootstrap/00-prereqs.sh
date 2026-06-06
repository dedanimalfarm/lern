#!/bin/bash
set -eo pipefail

echo "==> Проверка предварительных требований для лаборатории Kubernetes..."

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

pass() { echo -e "${GREEN}[OK]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

# 1. Проверка базовых CLI-инструментов
for cmd in kubectl jq helm openssl; do
  if command -v "$cmd" >/dev/null 2>&1; then
    pass "Утилита '$cmd' установлена"
  else
    fail "Утилита '$cmd' не найдена. Установите её перед продолжением."
  fi
done

if command -v sops >/dev/null 2>&1; then
  pass "Утилита 'sops' установлена (опционально)"
else
  echo -e "\033[0;33m[WARN]\033[0m Утилита 'sops' не найдена. Она потребуется только в Модуле 09 (Часть 5)."
fi

# 2. Проверка подключения к кластеру
if kubectl cluster-info >/dev/null 2>&1; then
  pass "Подключение к кластеру успешно"
else
  fail "Не удалось подключиться к кластеру. Проверьте переменную KUBECONFIG."
fi

# 3. Проверка версии Kubernetes (>= 1.30)
K8S_VERSION=$(kubectl version --output=json | jq -r '.serverVersion.minor' | sed 's/[^0-9]//g')
if [ "$K8S_VERSION" -ge 30 ]; then
  pass "Версия Kubernetes 1.${K8S_VERSION} (>= 1.30)"
else
  fail "Требуется Kubernetes версии 1.30 или выше. Текущая версия: 1.${K8S_VERSION}"
fi

# 4. Проверка namespace lab
if kubectl get ns lab >/dev/null 2>&1; then
  pass "Namespace 'lab' существует"
else
  echo "Создаю namespace 'lab'..."
  kubectl create ns lab
  pass "Namespace 'lab' создан"
fi

# 5. Проверка доступной оперативной памяти на нодах (>= 1.5GB)
# Это приблизительная проверка, т.к. kubectl top nodes может не показать
# реальную свободную память. Но мы можем проверить Capacity.
NODES=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')
for node in $NODES; do
  MEM_CAPACITY=$(kubectl get node "$node" -o jsonpath='{.status.capacity.memory}' | sed 's/Ki//')
  if [ "$MEM_CAPACITY" -ge 1500000 ]; then
    pass "Узел $node имеет >= 1.5GB памяти (${MEM_CAPACITY}Ki)"
  else
    echo -e "\033[0;33m[WARN]\033[0m Узел $node имеет менее 1.5GB памяти (${MEM_CAPACITY}Ki). Некоторые тяжелые аддоны (Istio/Gateway) могут не запуститься."
  fi
done

echo "==> Все предварительные требования выполнены успешно."
