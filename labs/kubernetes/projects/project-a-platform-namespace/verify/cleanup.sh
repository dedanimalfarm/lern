#!/usr/bin/env bash
set -euo pipefail
# Проект живёт в собственном ns platform (не lab) — generic clean-module его
# не трогает, убираем сами, чтобы прогоны были самодостаточными.
kubectl delete ns platform --ignore-not-found 2>/dev/null || true
echo "cleanup: removed project-a namespace platform"
