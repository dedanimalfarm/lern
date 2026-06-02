# Сценарий 01: target не появляется в Prometheus

## Симптом

Приложение и ServiceMonitor применены, поды Running, но в Prometheus
(Status → Targets) нет таргета `metrics-app`, и `up{job="metrics-app"}` пуст.

## Задание

1. Выясните, почему Prometheus-оператор игнорирует ваш ServiceMonitor.
2. Исправьте и убедитесь, что таргет появился.

<details>
<summary><strong>Подсказка</strong></summary>

kube-prometheus-stack настраивает Prometheus брать ServiceMonitor с конкретным
label (по умолчанию `release: <имя helm-релиза>`, здесь `kps`). Посмотрите
`serviceMonitorSelector` у объекта Prometheus:

```bash
kubectl -n monitoring get prometheus -o jsonpath='{.items[0].spec.serviceMonitorSelector}'
# {"matchLabels":{"release":"kps"}}
```

</details>

<details>
<summary><strong>Объяснение</strong></summary>

- Prometheus берёт только ServiceMonitor с label `release: kps`.
- Если у ServiceMonitor нет этого label — оператор его не подхватит, таргета нет.

</details>

<details>
<summary><strong>Решение</strong></summary>

Добавить label на ServiceMonitor:

```bash
kubectl -n lab label servicemonitor metrics-app release=kps --overwrite
# через ~30с таргет появится: up{job="metrics-app"} == 1
```

</details>
