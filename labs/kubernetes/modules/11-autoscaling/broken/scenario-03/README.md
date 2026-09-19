# Сценарий 03: HPA снова `<unknown>` — но requests на месте и metrics-server жив

## Симптом

```bash
kubectl -n lab get hpa hpa-demo
# NAME       REFERENCE             TARGETS         MINPODS   MAXPODS   REPLICAS   AGE
# hpa-demo   Deployment/hpa-demo   <unknown>/50%   1         5         1          2m
kubectl top pods -n lab            # метрики отдаются — metrics-server работает
kubectl -n lab get deploy hpa-demo -o jsonpath='{.spec.template.spec.containers[0].resources.requests}{"\n"}'
# {"cpu":"200m","memory":"64Mi"}   <- requests заданы
```

## Запуск

```bash
kubectl -n lab apply -f broken/scenario-03/deploy.yaml
kubectl -n lab apply -f manifests/hpa.yaml
sleep 60; kubectl -n lab get hpa hpa-demo; kubectl -n lab get pods -l app=hpa-demo
```

## Задание

1. Пройдите дерево диагностики `<unknown>` из Части 6: первые два шага (metrics-server, requests) проходят — что остаётся?
2. Посмотрите на сами поды: в каком они состоянии и почему.
3. Исправьте причину и дождитесь числа в колонке TARGETS.

Начните:

```bash
kubectl -n lab get pods -l app=hpa-demo
kubectl -n lab describe pod -l app=hpa-demo | grep -A5 '^Events' | tail -4
kubectl -n lab describe hpa hpa-demo | grep -A4 'Conditions'``
```

<details>
<summary><strong>Подсказка 1</strong></summary>

Метрики HPA берёт **только с Ready-подов**. Посмотрите колонки `READY` и `RESTARTS` у подов.

</details>

<details>
<summary><strong>Подсказка 2</strong></summary>

В событиях — `Liveness probe failed` и `Container ... failed liveness probe, will be restarted`: под не успевает стать Ready, kubelet его убивает, и HPA не с кого собирать метрики.

</details>

<details>
<summary><strong>Объяснение</strong></summary>

- В манифест добавлена агрессивная livenessProbe (`/definitely-missing`,
  `periodSeconds: 2`, `failureThreshold: 1`). Под уходит в цикл рестартов, `READY 0/1`.
- HPA считает утилизацию по подам, попавшим в метрики, а туда попадают только
  Ready-поды. Ни одного Ready — `TARGETS <unknown>`, условие
  `ScalingActive=False` с reason `FailedGetResourceMetric`.
- Это третий шаг дерева диагностики и самый неочевидный: и metrics-server, и
  `requests.cpu` в порядке, проблема — в здоровье подов. Сначала чините под,
  потом смотрите на HPA.

</details>

<details>
<summary><strong>Решение</strong></summary>

Убрать неверную пробу — `solutions/scenario-03/deploy.yaml`:

```bash
kubectl -n lab apply -f solutions/scenario-03/deploy.yaml
kubectl -n lab rollout status deploy/hpa-demo --timeout=120s
sleep 60; kubectl -n lab get hpa hpa-demo     # TARGETS: 0%/50%
```

</details>
