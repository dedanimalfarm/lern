# Сценарий 02: HPA показывает `<unknown>` и не масштабирует — при живом metrics-server

## Симптом

```bash
kubectl -n lab get hpa hpa-demo
# NAME       REFERENCE                 TARGETS        MINPODS   MAXPODS   REPLICAS   AGE
# hpa-demo   Deployment/hpa-demo-web   <unknown>/50%  1         5         0          1m   <- REPLICAS 0
kubectl top pods -n lab                # метрики есть — metrics-server в порядке
```

## Запуск

```bash
kubectl -n lab apply -k manifests/
kubectl -n lab apply -f broken/scenario-02/hpa.yaml
sleep 20; kubectl -n lab get hpa hpa-demo
```

## Задание

1. Пройдите дерево диагностики `<unknown>` из Части 6 — на каком шаге оно ломается здесь?
2. Найдите точную причину в `status.conditions` HPA.
3. Исправьте и дождитесь числового значения в `TARGETS`.

Начните:

```bash
kubectl -n lab describe hpa hpa-demo | grep -A6 '^Conditions'
kubectl -n lab get deploy
```

<details>
<summary><strong>Подсказка 1</strong></summary>

`AbleToScale: False / FailedGetScale: deployments/scale.apps "hpa-demo-web" not found` — HPA не может даже прочитать масштаб цели.

</details>

<details>
<summary><strong>Подсказка 2</strong></summary>

Сравните `scaleTargetRef.name` в HPA с реальным именем Deployment.

</details>

<details>
<summary><strong>Объяснение</strong></summary>

- В `scaleTargetRef.name` опечатка: `hpa-demo-web` вместо `hpa-demo`. HPA не находит объект,
  поэтому `REPLICAS 0`, `TARGETS <unknown>` и условие `AbleToScale=False`.
- metrics-server и requests тут ни при чём — это первый шаг диагностики, и он проходит.
- Тот же симптом даёт неверный `kind`/`apiVersion` в `scaleTargetRef`.

</details>

<details>
<summary><strong>Решение</strong></summary>

Исправить имя цели — `solutions/scenario-02/hpa.yaml`:

```bash
kubectl -n lab apply -f solutions/scenario-02/hpa.yaml
sleep 30; kubectl -n lab get hpa hpa-demo       # TARGETS: 0%/50%, REPLICAS 1
```

</details>
