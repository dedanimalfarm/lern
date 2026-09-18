#!/usr/bin/env bash
set -euo pipefail

kubectl get ns lab >/dev/null 2>&1 || kubectl create ns lab >/dev/null
kubectl -n lab get quota lab-quota >/dev/null 2>&1 || echo "prepare: нет ResourceQuota lab-quota — выполните bash scripts/bootstrap/01-apply-quotas.sh"
kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1 || { echo "Нет kube-prometheus-stack (CRD servicemonitors) — поднимите стек: scripts/cluster/up.sh --stacks"; exit 1; }
kubectl -n monitoring get prometheus >/dev/null 2>&1 || { echo "CRD есть, но объекта Prometheus в ns monitoring нет — проверьте helm-релиз kps"; exit 1; }
echo "prepare: kube-prometheus-stack на месте"
