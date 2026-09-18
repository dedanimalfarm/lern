# Сценарий 02: Rollout не завершается — CrashLoopBackOff

## Симптом

```bash
kubectl -n lab get pods -l app=workload-demo
# NAME                  READY   STATUS             RESTARTS      AGE
# workload-demo-...     0/1     CrashLoopBackOff   4 (30s ago)   2m   <- RESTARTS растёт
kubectl -n lab rollout status deploy/workload-demo --timeout=30s
# error: timed out waiting for the condition
```

## Запуск

```bash
kubectl -n lab apply -f broken/scenario-02/deploy.yaml
kubectl -n lab get pods -l app=workload-demo -w
```

## Задание

1. Определите, падает контейнер сам или его убивает Kubernetes.
2. Достаньте причину из логов **предыдущего** запуска и кода выхода.
3. Исправьте и убедитесь, что rollout завершился.

Начните:

```bash
kubectl -n lab logs deploy/workload-demo --previous
kubectl -n lab get pod -l app=workload-demo -o jsonpath='{.items[0].status.containerStatuses[0].lastState.terminated}{"\n"}'
```

<details>
<summary><strong>Подсказка 1</strong></summary>

`CrashLoopBackOff` — контейнер завершается, kubelet перезапускает его с растущей паузой. Текущий контейнер может ещё не успеть ничего написать — читайте `--previous`.

</details>

<details>
<summary><strong>Подсказка 2</strong></summary>

`lastState.terminated.exitCode=1` и `reason=Error` — приложение вышло само. Сравните `command` в манифесте с тем, что ожидает образ.

</details>

<details>
<summary><strong>Объяснение</strong></summary>

- В `command` контейнера подменена команда запуска: она печатает ошибку конфигурации
  и делает `exit 1`.
- Exit code 1 + reason `Error` = приложение упало само (в отличие от 137 — убит по
  памяти или пробой).
- Deployment держит старый ReplicaSet, пока новый не станет Ready, — rollout висит,
  `undo` вернул бы прошлую версию.

</details>

<details>
<summary><strong>Решение</strong></summary>

Убрать подменённый `command` (использовать команду образа) — `solutions/scenario-02/deploy.yaml`.

```bash
kubectl -n lab apply -f solutions/scenario-02/deploy.yaml
kubectl -n lab rollout status deploy/workload-demo --timeout=120s
```

</details>
