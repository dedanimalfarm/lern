# 01-install-stack

## Задача
Установить kube-prometheus-stack (Prometheus + Grafana + Alertmanager + exporters).

## Команды
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install kps prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace --wait
kubectl -n monitoring get pods
```

## Проверка
- Поды prometheus/grafana/alertmanager/node-exporter/kube-state-metrics — Running.
