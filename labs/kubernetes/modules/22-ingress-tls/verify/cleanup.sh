#!/usr/bin/env bash
set -euo pipefail

echo "=== Running module 22 cleanup ==="

echo "[INFO] Deleting lab namespace..."
kubectl delete ns lab --ignore-not-found

echo "[INFO] Deleting ClusterIssuers..."
kubectl delete clusterissuer selfsigned-issuer --ignore-not-found

echo "[INFO] Deleting ingress-nginx..."
kubectl delete ns ingress-nginx --ignore-not-found
kubectl delete clusterrole ingress-nginx --ignore-not-found
kubectl delete clusterrolebinding ingress-nginx --ignore-not-found
kubectl delete validatingwebhookconfiguration ingress-nginx-admission --ignore-not-found

echo "[INFO] Deleting cert-manager..."
kubectl delete ns cert-manager --ignore-not-found
kubectl delete clusterrole,clusterrolebinding -l app=cert-manager --ignore-not-found
kubectl delete clusterrole,clusterrolebinding -l app.kubernetes.io/instance=cert-manager --ignore-not-found
kubectl delete mutatingwebhookconfiguration cert-manager-webhook --ignore-not-found
kubectl delete validatingwebhookconfiguration cert-manager-webhook --ignore-not-found

echo "[INFO] Deleting cert-manager CRDs..."
kubectl get crd -o name | grep 'cert-manager.io' | xargs -r kubectl delete || true

echo "[OK] Cleanup complete."
