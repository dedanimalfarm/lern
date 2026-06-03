#!/usr/bin/env bash
set -euo pipefail

command -v kubectl &>/dev/null || { echo "kubectl not found"; exit 1; }
kubectl cluster-info --request-timeout=5s &>/dev/null || { echo "cluster not reachable"; exit 1; }

# Pinned ingress-nginx release for reproducible labs
VER="controller-v1.11.5"
# ВАЖНО: вариант BAREMETAL (NodePort), а НЕ cloud. На self-managed кластере без
# cloud-controller-manager (наш Kubespray на GCE) Service типа LoadBalancer из
# cloud-манифеста навсегда зависает в EXTERNAL-IP <pending>, и тогда контроллер не
# может проставить адрес в status Ingress -> объекты Ingress остаются без ADDRESS,
# а Argo CD считает их Progressing (модуль 09). Baremetal даёт NodePort без LB.
MANIFEST_URL="https://raw.githubusercontent.com/kubernetes/ingress-nginx/${VER}/deploy/static/provider/baremetal/deploy.yaml"

kubectl apply -f "$MANIFEST_URL"

# Чтобы объекты Ingress получали ADDRESS (без облачного LB), контроллер должен
# публиковать в их status internal-IP ноды, где он работает. Флаг идемпотентен.
if ! kubectl -n ingress-nginx get deploy ingress-nginx-controller \
      -o jsonpath='{.spec.template.spec.containers[0].args}' | grep -q -- '--report-node-internal-ip-address'; then
  kubectl -n ingress-nginx patch deploy ingress-nginx-controller --type=json \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--report-node-internal-ip-address"}]'
fi

kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=300s

echo "ingress-nginx ${VER} (baremetal/NodePort, --report-node-internal-ip-address) installed; IngressClass=nginx"
echo "Внешний доступ к NodePort требует firewall-правила на 30000-32767 (по умолчанию закрыт)."
