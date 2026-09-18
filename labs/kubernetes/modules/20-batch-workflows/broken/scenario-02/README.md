# Сценарий 02: Job падает через 5 секунд, хотя скрипт не ошибается

## Симптом

```bash
kubectl -n lab get job job-report
# NAME         STATUS   COMPLETIONS   DURATION   AGE
# job-report   Failed   0/1           5s         30s
kubectl -n lab get pods -l job-name=job-report
# job-report-xxxxx   0/1   Terminating/Error ...      <- под убит, а не упал
kubectl -n lab logs -l job-name=job-report --tail=2
# building report                               <- ошибок в логах нет
```

## Запуск

```bash
kubectl -n lab apply -f broken/scenario-02/job-deadline.yaml
kubectl -n lab get job job-report -w
```

## Задание

1. Найдите в статусе Job причину провала — это не `BackoffLimitExceeded` из сценария 01.
2. Объясните, почему ретраи (`backoffLimit: 3`) не помогли.
3. Исправьте так, чтобы отчёт достраивался, но зависший Job всё же не жил вечно.

Начните:

```bash
kubectl -n lab get job job-report -o jsonpath='{.status.conditions[*].reason}{"\n"}'
kubectl -n lab describe job job-report | grep -iE 'deadline|Warning'
```

<details>
<summary><strong>Подсказка 1</strong></summary>

`status.conditions[].reason = DeadlineExceeded`: Job превысил `activeDeadlineSeconds` — это лимит на **весь** Job, включая все попытки.

</details>

<details>
<summary><strong>Подсказка 2</strong></summary>

По истечении deadline Job переходит в Failed и убивает все поды; новые попытки не создаются, `backoffLimit` уже не при чём.

</details>

<details>
<summary><strong>Объяснение</strong></summary>

- `activeDeadlineSeconds: 5` при работе на 60 с — Job гарантированно не успевает. Deadline
  считается от старта Job, действует поверх ретраев и завершает всё принудительно.
- Отличие от сценария 01: там поды падали сами (exit≠0) и кончились ретраи
  (`BackoffLimitExceeded`); здесь скрипт исправен, а Job убит по таймеру
  (`DeadlineExceeded`).
- `activeDeadlineSeconds` нужен как страховка от зависших задач — ставить его с запасом
  от реальной длительности, а для «мягкого» ограничения попыток есть `backoffLimit`.

</details>

<details>
<summary><strong>Решение</strong></summary>

Поднять deadline до разумного запаса — `solutions/scenario-02/job-deadline.yaml` (300 с):

```bash
kubectl -n lab delete job job-report
kubectl -n lab apply -f solutions/scenario-02/job-deadline.yaml
kubectl -n lab wait --for=condition=complete job/job-report --timeout=120s
```

</details>
