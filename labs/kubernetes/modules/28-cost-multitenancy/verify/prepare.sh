#!/usr/bin/env bash
set -euo pipefail

# HNC и vcluster приезжают из manifests/ (vendored, версии запинованы).
# prepare лишь гарантирует базовый namespace лабы.
kubectl create ns lab --dry-run=client -o yaml | kubectl apply -f - >/dev/null
echo "prepare: namespace lab ensured"
