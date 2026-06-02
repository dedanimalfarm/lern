# Сценарий 01: реплика в Pending из-за required anti-affinity

## Симптом

Деплой из 3 реплик, но `READY` = 2/3: одна реплика вечно в `Pending`, хотя
ресурсы на нодах есть.

## Запуск

```bash
kubectl -n lab apply -f deploy.yaml
kubectl -n lab get pods -l app=resilient-app -o wide
# 2 Running (на разных нодах) + 1 Pending
```

## Задание

1. Выясните, почему 3-я реплика не планируется.
2. Решите, не теряя идею «реплики на разных нодах».

Начните:

```bash
kubectl -n lab describe pod -l app=resilient-app | grep -A2 FailedScheduling
```

<details>
<summary><strong>Подсказка</strong></summary>

`requiredDuringScheduling` podAntiAffinity по `kubernetes.io/hostname` ОБЯЗЫВАЕТ
держать реплики на разных нодах. Сколько у вас нод, на которые под реально может
сесть? (control-plane нода с taint — не в счёт.)

</details>

<details>
<summary><strong>Объяснение</strong></summary>

- `required` anti-affinity: каждая реплика — на отдельной ноде, иначе не сядет.
- Доступных worker-нод 2 (control-plane с taint исключена) → 2 реплики сели на
  разные ноды, 3-й «свободной разной» ноды нет → `Pending`.
- `describe pod` → `FailedScheduling ... didn't match pod anti-affinity rules`.

</details>

<details>
<summary><strong>Решение</strong></summary>

Сделать anti-affinity МЯГКИМ (`preferred`) — scheduler разведёт по нодам, но при
нехватке всё равно посадит:

```bash
kubectl -n lab apply -f ../../solutions/01-spread-pending/deploy.yaml
kubectl -n lab get pods -l app=resilient-app -o wide   # все 3 Running (2/1)
```

(Альтернатива — добавить ноду, чтобы хватило «разных».)

</details>
