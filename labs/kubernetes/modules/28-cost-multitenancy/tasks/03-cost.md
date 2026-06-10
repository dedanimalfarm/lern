# Задание 3: Стоимость по namespace (FinOps на PromQL)

Деньги в Kubernetes считаются от **requests** (бронь ёмкости), а не от
фактического потребления: забронированное ядро нельзя продать другому тенанту.
Посчитаем «прайс» нашего стенда и стоимость каждого namespace.

Цена e2-medium в us-central1 — ~$0.0335/час за 2 vCPU + 4 GB. Разложим её на
компоненты (примерно 2/3 на CPU, 1/3 на RAM):
**1 vCPU-час ≈ $0.0112, 1 GiB-час ≈ $0.0028.**

## Практика

```bash
kubectl -n monitoring port-forward svc/kps-kube-prometheus-stack-prometheus 19090:9090 &
```

Запросы в Prometheus (UI на http://localhost:19090 или через curl):

```promql
# CPU-requests по namespace (ядра)
sum by (namespace) (kube_pod_container_resource_requests{resource="cpu", unit="core"})

# RAM-requests по namespace (GiB)
sum by (namespace) (kube_pod_container_resource_requests{resource="memory", unit="byte"}) / 2^30

# Стоимость namespace, $/час (showback!)
sum by (namespace) (kube_pod_container_resource_requests{resource="cpu", unit="core"}) * 0.0112
  + sum by (namespace) (kube_pod_container_resource_requests{resource="memory", unit="byte"}) / 2^30 * 0.0028
```

Найдите overprovisioning (бронь, которая не используется):

```promql
# Фактическое потребление CPU по namespace
sum by (namespace) (rate(container_cpu_usage_seconds_total{container!=""}[10m]))
```

Сравните с requests: на нашем стенде ns `lab` обычно потребляет ~0.07 ядра при
брони 0.32 — утилизация ~23%. В проде такой разрыв = прямые потери денег;
лечится rightsizing'ом (правкой requests) или автоматикой VPA (модуль 11).
