# Сценарий 02: Новые поды висят в Pending, хотя ресурсов полно

## Симптом

После «планового обслуживания» команда масштабирует приложение, но новые реплики не
запускаются:

```bash
kubectl -n lab get pods -l app=drain-demo
# NAME            READY   STATUS    RESTARTS   AGE
# drain-demo-…    1/1     Running   0          10m     <- старый под работает
# drain-demo-…    0/1     Pending   0          30s     <- новые — Pending
# drain-demo-…    0/1     Pending   0          30s
kubectl top nodes            # CPU/RAM свободны
```

## Запуск

```bash
bash broken/scenario-02/setup.sh
kubectl -n lab get pods -l app=drain-demo
```

## Задание

1. Выясните из событий пода, почему планировщик не находит ноду.
2. Проверьте состояние нод — не только `Ready`.
3. Верните ноды в строй и убедитесь, что реплики поднялись.

Начните:

```bash
kubectl -n lab describe pod -l app=drain-demo | grep -A3 '^Events' | tail -4
kubectl get nodes
```

<details>
<summary><strong>Подсказка 1</strong></summary>

`FailedScheduling: 0/3 nodes are available: 2 node(s) were unschedulable, 1 node(s) had untolerated taint {node-role.kubernetes.io/control-plane}` — дело не в ресурсах.

</details>

<details>
<summary><strong>Подсказка 2</strong></summary>

Колонка `STATUS` в `kubectl get nodes` показывает `Ready,SchedulingDisabled` — это след `cordon`, который забыли снять после drain.

</details>

<details>
<summary><strong>Объяснение</strong></summary>

- `kubectl cordon`/`drain` помечает ноду `unschedulable: true`: работающие поды остаются,
  но новые на неё не планируются. Если после обслуживания не сделать `uncordon`, нода
  «выпадает» из ёмкости кластера тихо — `Ready` она по-прежнему.
- Планировщик отвечает `node(s) were unschedulable`; на статичном стенде без Cluster
  Autoscaler поды будут ждать вечно.
- Руководство: drain и uncordon — парные операции, их стоит держать в одном runbook и
  проверять `SchedulingDisabled` в мониторинге.

</details>

<details>
<summary><strong>Решение</strong></summary>

Снять cordon со всех нод — `solutions/scenario-02/fix.sh`:

```bash
bash solutions/scenario-02/fix.sh
kubectl get nodes                                  # без SchedulingDisabled
kubectl -n lab get pods -l app=drain-demo          # 3/3 Running
```

</details>
