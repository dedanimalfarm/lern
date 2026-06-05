# 01 — Parallelism и completions

## Задача
Запустить Job на 6 единиц работы, пропуская не более 2 подов одновременно, и
увидеть «волны» по 2 пода (3 волны => 6 завершений).

## Проверка
```bash
kubectl -n lab apply -f manifests/parallel/job-parallel.yaml
# Наблюдать волны: одновременно не больше 2 Running
kubectl -n lab get pods -l job-name=job-parallel -w
kubectl -n lab get job job-parallel
# COMPLETIONS 6/6, STATUS Complete

# Эксперимент: поднять parallelism до 6 в манифесте -> все 6 подов разом.
# Поднять completions без parallelism -> та же пропускная способность, но больше работы.
```

## Ожидаемый результат
`succeeded=6`, condition `Complete`. В любой момент Running ≤ parallelism.
