# 03 — Limits enforcement (CPU throttle vs Memory OOM)

## Задача
Увидеть, что превышение limits.memory -> OOMKilled (memory несжимаема), а CPU
сверх лимита -> throttling (под жив).

## Проверка
```bash
kubectl -n lab apply -f broken/scenario-01/oom-pod.yaml   # limit 32Mi, нагрузка 100Mi -> OOMKilled
kubectl -n lab get pod mem-hog -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}{"\n"}'
kubectl -n lab delete pod mem-hog
kubectl -n lab apply -f solutions/01-oom/oom-pod.yaml      # limit 256Mi -> Completed
```
