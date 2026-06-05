# 03 — podFailurePolicy, deadline и CronJob

## Задача A — fail-fast по коду выхода
Сделать Job, который на «фатальном» exit-коде падает СРАЗУ (FailJob), не тратя
весь `backoffLimit`.

```bash
kubectl -n lab apply -f - <<'EOF'
apiVersion: batch/v1
kind: Job
metadata: { name: failfast, namespace: lab }
spec:
  backoffLimit: 6
  podFailurePolicy:
    rules:
    - action: FailJob
      onExitCodes: { operator: In, values: [42] }
  template:
    spec:
      restartPolicy: Never
      containers: [{ name: w, image: busybox:1.36, command: ["sh","-c","exit 42"] }]
EOF
kubectl -n lab get job failfast \
  -o jsonpath='{.status.conditions[*].reason}{"\n"}'   # PodFailurePolicy (а не BackoffLimitExceeded)
kubectl -n lab delete job failfast
```

## Задача B — CronJob и concurrencyPolicy
```bash
kubectl -n lab apply -f manifests/cron/cronjob.yaml
# Подождать ~1-2 мин, увидеть, что CronJob тикнул и породил Job:
kubectl -n lab get cronjob batch-report     # LAST SCHEDULE заполнится
kubectl -n lab get jobs | grep batch-report # Job-ы по префиксу имени (метки cronjob-name нет)
# Проверить, что Forbid не даёт наложений; история ограничена History-лимитами.
```

## Ожидаемый результат
A: Job `Failed` с `reason=PodFailurePolicy`, `failed=1` (не 7).
B: CronJob создаёт по одному Job на тик; старые Job подчищаются по history-лимитам.
