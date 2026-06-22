#!/usr/bin/env bash
set -euo pipefail

echo "=== Running module 22 verification ==="

if ! kubectl get ns lab >/dev/null 2>&1; then
    echo "[FAIL] Namespace 'lab' does not exist."
    exit 1
fi

for app in web-a web-b; do
    if ! kubectl -n lab get deploy $app >/dev/null 2>&1; then
        echo "[FAIL] Deployment $app not found in namespace lab."
        exit 1
    fi
    kubectl -n lab rollout status deploy/$app --timeout=30s >/dev/null 2>&1 || { echo "[FAIL] Deployment $app is not ready."; exit 1; }
done
echo "[OK] web-a and web-b Deployments are ready."

if ! kubectl -n lab get ingress web-routing >/dev/null 2>&1; then
    echo "[FAIL] Ingress 'web-routing' not found."
    exit 1
fi

INGRESS_CLASS=$(kubectl -n lab get ingress web-routing -o jsonpath='{.spec.ingressClassName}')
if [[ "$INGRESS_CLASS" != "nginx" ]]; then
    echo "[FAIL] Ingress 'web-routing' has incorrect ingressClassName: '$INGRESS_CLASS', expected 'nginx'."
    exit 1
fi
echo "[OK] Ingress web-routing found with class 'nginx'."

if ! kubectl -n ingress-nginx get deploy ingress-nginx-controller >/dev/null 2>&1; then
    echo "[FAIL] ingress-nginx controller not found."
    exit 1
fi
echo "[OK] ingress-nginx controller is present."

if ! kubectl get crd certificates.cert-manager.io >/dev/null 2>&1; then
    echo "[WARN] cert-manager CRDs not found, skipping TLS checks."
else
    if kubectl -n lab get certificate auto-tls >/dev/null 2>&1; then
        READY=$(kubectl -n lab get certificate auto-tls -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
        if [[ "$READY" == "True" ]]; then
            echo "[OK] Certificate 'auto-tls' is Ready."
        else
            echo "[WARN] Certificate 'auto-tls' is not Ready."
        fi
    else
        echo "[WARN] Certificate 'auto-tls' not found."
    fi

    if kubectl -n lab get secret auto-tls >/dev/null 2>&1; then
        echo "[OK] Secret 'auto-tls' is present."
    else
        echo "[WARN] Secret 'auto-tls' not found."
    fi
fi

echo "[OK] module 22 verified"
