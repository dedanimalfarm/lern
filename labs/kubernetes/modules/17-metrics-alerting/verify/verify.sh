#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin kubectl
require_namespace lab
kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1 || fail "нет kube-prometheus-stack (CRD servicemonitors) — scripts/cluster/up.sh --stacks"
kubectl -n monitoring get svc kps-kube-prometheus-stack-prometheus >/dev/null 2>&1 || fail "нет Service kps-kube-prometheus-stack-prometheus в ns monitoring — helm-релиз kps не установлен"
require_deployment_ready lab metrics-app 120s
require_resource lab servicemonitor metrics-app
require_resource lab prometheusrule metrics-app-rules
ok "Part 2: metrics-app, ServiceMonitor и PrometheusRule на месте"

PROM=http://kps-kube-prometheus-stack-prometheus.monitoring.svc:9090
kubectl -n lab delete pod verify-curl --ignore-not-found --force --grace-period=0 >/dev/null 2>&1 || true
OUT=$(kubectl -n lab run verify-curl --rm -i --restart=Never --quiet --image=curlimages/curl:8.10.1 -- sh -c "
  for i in \$(seq 1 30); do
    curl -s -m 5 '$PROM/api/v1/query?query=up%7Bjob%3D%22metrics-app%22%7D' | grep -q '\"1\"' && break
    sleep 10
  done
  echo UP=\$(curl -s -m 5 '$PROM/api/v1/query?query=up%7Bjob%3D%22metrics-app%22%7D' | grep -o '\"value\":\[[^]]*\]' | head -1)
  echo TARGET=\$(curl -s -m 5 '$PROM/api/v1/targets?state=active' | grep -o 'serviceMonitor/lab/metrics-app/[0-9]*' | head -1)
  echo RULE=\$(curl -s -m 5 '$PROM/api/v1/rules?type=alert' | grep -o '\"name\":\"MetricsAppDown\"' | head -1)
  echo RATE=\$(curl -s -m 5 '$PROM/api/v1/query?query=sum(rate(http_requests_total%7Bjob%3D%22metrics-app%22%7D%5B1m%5D))' | grep -o '\"resultType\":\"vector\"' | head -1)
" 2>/dev/null || true)
grep -q '^UP=.*"1"' <<<"$OUT" || fail "Prometheus не видит metrics-app как up=1 за 5 минут (ServiceMonitor не подхвачен? метка release=kps?), получили: $(grep '^UP=' <<<"$OUT" || true)"
grep -q '^TARGET=serviceMonitor/lab/metrics-app/' <<<"$OUT" || fail "в активных таргетах нет serviceMonitor/lab/metrics-app: $(grep '^TARGET=' <<<"$OUT" || true)"
grep -q '^RULE="name":"MetricsAppDown"' <<<"$OUT" || fail "PrometheusRule metrics-app-rules не загружен в Prometheus (алерт MetricsAppDown не найден в /api/v1/rules)"
grep -q '^RATE="resultType":"vector"' <<<"$OUT" || fail "PromQL sum(rate(http_requests_total{job=\"metrics-app\"}[1m])) не выполняется"
ok "Part 3: таргет serviceMonitor/lab/metrics-app UP, правило MetricsAppDown загружено, PromQL по http_requests_total работает"

ok "module 17 verified"
