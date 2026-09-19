# Сценарий 03: Контейнер перезапускается, в логах пусто

## Симптом

```bash
kubectl -n lab get pods -l app=kb-web
# NAME             READY   STATUS      RESTARTS      AGE
# kb-web-...       0/1     OOMKilled   3 (20s ago)   70s
kubectl -n lab logs deploy/kb-web --tail=5
#                                            <- ни одной строки об ошибке
```

## Запуск

```bash
kubectl -n lab apply -f broken/scenario-03/deploy.yaml
kubectl -n lab get pods -l app=kb-web -w
```

## Задание

1. Определите по статусу и коду выхода, кто завершил контейнер: приложение, kubelet или ядро.
2. Найдите в манифесте параметр, который к этому привёл.
3. Исправьте и убедитесь, что рестарты прекратились.

Начните:

```bash
kubectl -n lab get pod -l app=kb-web \
  -o jsonpath='{.items[0].status.containerStatuses[0].lastState.terminated}{"\n"}'
kubectl -n lab describe pod -l app=kb-web | grep -A4 'Last State'
kubectl -n lab get deploy kb-web -o jsonpath='{.spec.template.spec.containers[0].resources}{"\n"}'
```

<details>
<summary><strong>Подсказка 1</strong></summary>

Колонка `STATUS` и `lastState.terminated.reason` называют причину прямым текстом. Код выхода 137 = 128 + 9 (SIGKILL): процесс не завершался сам, его убили.

</details>

<details>
<summary><strong>Подсказка 2</strong></summary>

SIGKILL по памяти шлёт не Kubernetes, а cgroup-контроллер ядра, когда контейнер превышает `limits.memory`. Сравните лимит в манифесте с тем, сколько нужно nginx.

</details>

<details>
<summary><strong>Объяснение</strong></summary>

- В манифесте `limits.memory: 8Mi` (и такой же `requests`). nginx поднимает master- и
  worker-процессы и сразу вылезает за лимит — ядро убивает контейнер, kubelet
  перезапускает, счётчик `RESTARTS` растёт.
- Диагностический признак OOM: `reason: OOMKilled`, `exitCode: 137`, пустые логи
  (приложение не успевает ничего сказать). Это отличает случай от `CrashLoopBackOff`
  с `exitCode: 1`, где приложение падает само и обычно пишет ошибку.
- `requests.memory` тут не спасает: он влияет только на планирование, а убивает
  превышение **limits**.

</details>

<details>
<summary><strong>Решение</strong></summary>

Вернуть адекватный лимит памяти — `solutions/scenario-03/deploy.yaml`:

```bash
kubectl -n lab apply -f solutions/scenario-03/deploy.yaml
kubectl -n lab rollout status deploy/kb-web --timeout=90s
kubectl -n lab get pods -l app=kb-web      # 1/1 Running, RESTARTS не растёт
```

</details>
