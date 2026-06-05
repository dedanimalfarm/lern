# 02 — Indexed Job и партиционирование

## Задача
Запустить Indexed Job на 4 шарда и убедиться, что каждый под получил свой
уникальный `JOB_COMPLETION_INDEX` (0..3) — статическое разделение работы без
внешней очереди.

## Проверка
```bash
kubectl -n lab apply -f manifests/indexed/job-indexed.yaml
kubectl -n lab wait --for=condition=complete job/job-indexed --timeout=120s

# Каждый под напечатал свой шард — индексы не пересекаются:
kubectl -n lab logs -l job-name=job-indexed --prefix --tail=1 | sort
# shard 0 of 4 ...  shard 1 of 4 ...  shard 2 of 4 ...  shard 3 of 4 ...

# Завершённые индексы и режим:
kubectl -n lab get job job-indexed \
  -o jsonpath='mode={.spec.completionMode} indexes={.status.completedIndexes}{"\n"}'
# mode=Indexed indexes=0-3
```

## Ожидаемый результат
`completionMode=Indexed`, `completedIndexes=0-3`, по одному поду на индекс.
