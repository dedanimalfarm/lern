# 01 — Native sidecar в Job

## Задача
Увидеть, что native sidecar (init + `restartPolicy: Always`) НЕ держит Job живым:
app завершается → sidecar гасится → Job Complete.

## Проверка
```bash
kubectl -n lab apply -f manifests/sidecar/job.yaml
kubectl -n lab get pod -l job-name=sidecar-job -w   # 2/2 Running -> app выходит -> под завершается
kubectl -n lab wait --for=condition=complete job/sidecar-job --timeout=60s
kubectl -n lab get job sidecar-job                  # Complete 1/1

# Сравни с антипаттерном (broken/scenario-01): тот же логгер в containers[] -> Job висит вечно.
```

## Ожидаемый результат
Job `Complete`; initContainer logshipper имеет `restartPolicy: Always`.
