#!/usr/bin/env bash
set -euo pipefail

command -v kubectl &>/dev/null || { echo "kubectl not found"; exit 1; }
kubectl cluster-info --request-timeout=5s &>/dev/null || { echo "cluster not reachable"; exit 1; }

# Pinned version for reproducible labs
MANIFEST_URL="https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.7.2/components.yaml"

kubectl apply -f "$MANIFEST_URL"

# На self-managed кластерах (Kubespray, kind, kubeadm без rotate-server-certs)
# kubelet отдаёт САМОПОДПИСАННЫЙ serving-сертификат на :10250, не подписанный
# кластерным CA. Без --kubelet-insecure-tls metrics-server не может его проверить
# и падает с x509 "certificate signed by unknown authority" -> метрик нет,
# `kubectl top` и HPA по ресурсам не работают (модули 08/11). Managed-кластеры
# (GKE и т.п.) дают валидный kubelet-cert, и флаг там не нужен — но он безвреден.
# Патч идемпотентен: добавляем флаг только если его ещё нет.
if ! kubectl -n kube-system get deploy metrics-server \
      -o jsonpath='{.spec.template.spec.containers[0].args}' | grep -q -- '--kubelet-insecure-tls'; then
  kubectl -n kube-system patch deploy metrics-server --type=json \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
fi

kubectl -n kube-system rollout status deploy/metrics-server --timeout=180s

echo "metrics-server v0.7.2 installed (--kubelet-insecure-tls for self-managed kubelet certs)"
