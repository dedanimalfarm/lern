# 02-promql

## Задача
Поработать с PromQL через Prometheus UI.

## Команды
```bash
kubectl -n monitoring port-forward svc/kps-kube-prometheus-stack-prometheus 9090 &
# открыть http://localhost:9090 -> Graph
```

## Запросы
- `up` — какие таргеты живы (1/0).
- `up{job="metrics-app"}` — наш таргет.
- `sum(rate(http_requests_total{job="metrics-app"}[1m]))` — rate запросов.
- `kube_pod_status_phase{namespace="lab"}` — фазы подов (kube-state-metrics).
