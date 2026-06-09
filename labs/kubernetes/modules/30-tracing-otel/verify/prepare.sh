#!/usr/bin/env bash
# Подготовка перед apply манифестов (вызывается run-module.sh).
# Datasource-секреты модуля живут в ns monitoring (стек модулей 17/18);
# если стек не установлен — создаём пустой ns, секреты полежат до установки.
set -euo pipefail

kubectl create ns lab --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl create ns monitoring --dry-run=client -o yaml | kubectl apply -f - >/dev/null
echo "prepare: namespaces lab/monitoring ensured"
