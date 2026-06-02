# 03-servicemonitor-alert

## Задача
Подключить своё приложение к Prometheus (ServiceMonitor) и завести алерт.

## Команды
```bash
kubectl -n lab apply -f manifests/app.yaml
kubectl -n lab apply -f manifests/servicemonitor.yaml   # label release=kps!
kubectl -n lab apply -f manifests/prometheusrule.yaml

# проверить, что таргет появился (Status -> Targets в Prometheus UI):
#   up{job="metrics-app"} == 1
```

## Проверка
- В Prometheus есть таргет `metrics-app` (state UP).
- Правило `MetricsAppDown` видно в Alerts.
