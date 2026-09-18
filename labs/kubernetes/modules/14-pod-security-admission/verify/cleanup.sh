#!/usr/bin/env bash
set -euo pipefail

for ns in lab lab-restricted; do
  kubectl -n "$ns" delete pod bad bad-notag good-tag no-owner test test-shell warn-pod with-owner --ignore-not-found --force --grace-period=0 >/dev/null 2>&1 || true
done
kubectl -n lab-restricted delete pod --all --ignore-not-found >/dev/null 2>&1 || true
kubectl delete validatingadmissionpolicybinding no-latest-tag-binding --ignore-not-found >/dev/null 2>&1 || true
kubectl delete validatingadmissionpolicy no-latest-tag --ignore-not-found >/dev/null 2>&1 || true
echo "cleanup: готово (namespace lab-restricted сохранён — это baseline стенда)"
