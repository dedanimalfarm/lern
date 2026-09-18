# Сценарий 02: Поды Deployment вечно Pending без единого события

## Симптом

```bash
kubectl -n lab get pods -l app=gated-web
# NAME               READY   STATUS            RESTARTS   AGE
# gated-web-...      0/1     SchedulingGated   0          2m
# gated-web-...      0/1     SchedulingGated   0          2m
kubectl -n lab describe pod -l app=gated-web | grep -A2 '^Events'
# Events:  <none>                                <- планировщик их даже не видел
```

## Запуск

```bash
kubectl -n lab apply -f broken/scenario-02/deploy-gated.yaml
kubectl -n lab get pods -l app=gated-web
```

## Задание

1. Объясните, чем `SchedulingGated` отличается от обычного `Pending` с `FailedScheduling`.
2. Найдите, кто должен снимать gate, и почему патч самих подов здесь не поможет надолго.
3. Исправьте так, чтобы новые реплики тоже планировались.

Начните:

```bash
kubectl -n lab get pod -l app=gated-web -o jsonpath='{.items[0].spec.schedulingGates}{"\n"}'
kubectl -n lab get pod -l app=gated-web -o jsonpath='{.items[0].status.conditions[?(@.type=="PodScheduled")].reason}{"\n"}'
```

<details>
<summary><strong>Подсказка 1</strong></summary>

`status.conditions[PodScheduled].reason = SchedulingGated`: под создан, но исключён из очереди планировщика, пока список `schedulingGates` не пуст.

</details>

<details>
<summary><strong>Подсказка 2</strong></summary>

Gate снимает внешний контроллер (например, Kueue после проверки квоты). В шаблоне Deployment gate есть, а контроллера нет — каждый новый под рождается заблокированным.

</details>

<details>
<summary><strong>Объяснение</strong></summary>

- Scheduling gates (GA 1.30) — способ «придержать» под до внешнего решения. Kubernetes сам
  их не снимает: это обязанность контроллера, который их поставил.
- Патч `schedulingGates: []` на существующих подах пустит их, но ReplicaSet создаёт новые
  поды из того же шаблона — и они снова будут `SchedulingGated`. Чинить надо шаблон
  (или запускать контроллер-«привратник»).
- Симптом отличается от `FailedScheduling`: событий нет, ресурсы ни при чём.

</details>

<details>
<summary><strong>Решение</strong></summary>

Убрать gate из шаблона (контроллера-привратника на стенде нет) — `solutions/scenario-02/deploy-gated.yaml`:

```bash
kubectl -n lab apply -f solutions/scenario-02/deploy-gated.yaml
kubectl -n lab rollout status deploy/gated-web --timeout=60s
```

</details>
