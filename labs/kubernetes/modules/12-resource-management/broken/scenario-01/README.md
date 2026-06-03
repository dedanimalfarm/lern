# Инцидент: Pod падает с OOMKilled

`kubectl -n lab apply -f broken/scenario-01/oom-pod.yaml` — контейнер аллоцирует
~100Mi при `limits.memory: 32Mi`.

## Симптом
```bash
kubectl -n lab get pod mem-hog
# mem-hog   0/1   OOMKilled   0   ...     (или Error/CrashLoop при restartPolicy)
kubectl -n lab get pod mem-hog -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}{"\n"}'
# OOMKilled
```

## Причина
Memory — НЕсжимаемый ресурс: при превышении `limits.memory` cgroup НЕ тормозит
процесс (как с CPU), а УБИВАЕТ его (exit 137). Лимит был меньше реального
потребления приложения.

## Решение
`solutions/01-oom/oom-pod.yaml` — поднять `limits.memory` до реального footprint
(256Mi). Альтернатива в проде: чинить утечку/уменьшать потребление приложения.
