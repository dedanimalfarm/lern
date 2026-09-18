# Сценарий 02: Приложение живо, а под рестартует каждые несколько секунд

## Симптом

```bash
kubectl -n lab get pods -l app=obs-demo
# NAME             READY   STATUS    RESTARTS      AGE
# obs-demo-...     1/1     Running   6 (10s ago)   90s    <- Running, но RESTARTS растёт
kubectl -n lab logs deploy/obs-demo --previous | tail -2
# level=info msg="tick"                                    <- в логах ни одной ошибки
```

## Запуск

```bash
kubectl -n lab apply -f broken/scenario-02/deploy.yaml
kubectl -n lab get pods -l app=obs-demo -w
```

## Задание

1. Докажите, что приложение не падает само: чем отличается этот случай от CrashLoopBackOff из сценария 01?
2. Найдите, кто и за что убивает контейнер.
3. Исправьте манифест так, чтобы рестарты прекратились.

Начните:

```bash
kubectl -n lab describe pod -l app=obs-demo | grep -A6 '^Events'
kubectl -n lab get pod -l app=obs-demo -o jsonpath='{.items[0].status.containerStatuses[0].lastState.terminated.exitCode}{"\n"}'
```

<details>
<summary><strong>Подсказка 1</strong></summary>

В Events — `Liveness probe failed: ... connection refused` и `Container app failed liveness probe, will be restarted`. Логи приложения чистые: убивает kubelet.

</details>

<details>
<summary><strong>Подсказка 2</strong></summary>

Код выхода 137/143 (SIGKILL/SIGTERM) вместо 1 — контейнер остановлен снаружи. Проверьте, есть ли у приложения вообще HTTP-порт, в который стучится проба.

</details>

<details>
<summary><strong>Объяснение</strong></summary>

- В манифест добавлена livenessProbe с `httpGet` на порт 80 и путь `/definitely-missing`,
  `periodSeconds: 2`, `failureThreshold: 1`. Приложение — логгер на busybox без HTTP-сервера.
- Проба проваливается с первой попытки → kubelet убивает контейнер → рестарт → счётчик растёт,
  хотя приложение здорово.
- Диагностический признак: `Liveness probe failed` в Events + exit code 137/143 при пустых
  логах ошибок. Слишком строгая liveness — классическая причина «самопроизвольных» рестартов.

</details>

<details>
<summary><strong>Решение</strong></summary>

Убрать неверную пробу (или дать приложению реальный health-эндпоинт и разумные
`initialDelaySeconds`/`failureThreshold`) — `solutions/scenario-02/deploy.yaml`.

```bash
kubectl -n lab apply -f solutions/scenario-02/deploy.yaml
kubectl -n lab get pods -l app=obs-demo -w     # RESTARTS больше не растёт
```

</details>
