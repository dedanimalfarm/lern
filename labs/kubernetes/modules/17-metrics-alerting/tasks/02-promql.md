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
## Ожидаемый результат
- `up{job="metrics-app"}` = `1`; `sum(rate(http_requests_total{job="metrics-app"}[1m]))`
  даёт ненулевое число запросов в секунду.
- Вы объяснили, почему `rate` требует диапазон `[1m]` и что вернёт `rate` на окне
  короче двух интервалов scrape.
- `kube_pod_status_phase{namespace="lab"}` содержит по одной серии на каждую фазу для
  каждого пода, и только одна из них равна `1` — вы записали запрос, который считает
  число подов в `Running`.
