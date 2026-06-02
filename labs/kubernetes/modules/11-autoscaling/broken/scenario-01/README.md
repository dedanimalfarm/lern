# Сценарий 01

## Симптом

HorizontalPodAutoscaler создан, нагрузка идёт, но число реплик не растёт.
`kubectl get hpa` показывает в колонке TARGETS значение `<unknown>/50%`.

## Запуск

```bash
kubectl -n lab apply -f deploy.yaml          # Deployment БЕЗ requests.cpu
kubectl -n lab apply -f ../../manifests/hpa.yaml
kubectl -n lab get hpa hpa-demo -w
```

## Задание

1. Выясните, почему HPA не может вычислить метрику.
2. Найдите, чего не хватает в Deployment.
3. Исправьте, чтобы TARGETS показал реальный процент.

Начните:

```bash
kubectl -n lab describe hpa hpa-demo
kubectl -n lab get deploy hpa-demo -o jsonpath='{.spec.template.spec.containers[0].resources}'
```

<details>
<summary><strong>Подсказка 1</strong></summary>

HPA по CPU-утилизации считает процент как `usage / requests`.
Что будет, если `requests.cpu` не задан — на что делить?

</details>

<details>
<summary><strong>Подсказка 2</strong></summary>

Посмотрите события HPA:

```bash
kubectl -n lab describe hpa hpa-demo | grep -A3 Events
# FailedGetResourceMetric ... missing request for cpu
```

</details>

<details>
<summary><strong>Объяснение</strong></summary>

- HPA с `target.averageUtilization` считает процент от `requests.cpu`.
- В Deployment `requests.cpu` отсутствует → знаменателя нет.
- HPA не может вычислить метрику → TARGETS `<unknown>` → масштабирования нет.

</details>

<details>
<summary><strong>Решение</strong></summary>

Добавить `resources.requests.cpu` в контейнер.

```bash
kubectl -n lab apply -f ../../solutions/01-no-requests/deploy.yaml
kubectl -n lab get hpa hpa-demo        # TARGETS станет, напр., 0%/50%
```

</details>
