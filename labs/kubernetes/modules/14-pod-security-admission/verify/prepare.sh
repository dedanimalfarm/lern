#!/usr/bin/env bash
set -euo pipefail

kubectl get ns lab >/dev/null 2>&1 || kubectl create ns lab >/dev/null
kubectl -n lab get quota lab-quota >/dev/null 2>&1 || echo "prepare: нет ResourceQuota lab-quota — выполните bash scripts/bootstrap/01-apply-quotas.sh"
kubectl api-resources --api-group=admissionregistration.k8s.io 2>/dev/null | grep -q validatingadmissionpolicies || { echo "ValidatingAdmissionPolicy недоступен — нужен Kubernetes >= 1.30"; exit 1; }
echo "prepare: PSA и ValidatingAdmissionPolicy доступны"
