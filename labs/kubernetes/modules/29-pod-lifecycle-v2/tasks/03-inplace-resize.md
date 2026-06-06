# 03 — In-place resize (вертикальный скейл без рестарта)

## Задача
Поднять CPU работающему поду БЕЗ пересоздания. Понять два ограничения, которые
ловят всех: (1) нельзя менять QoS-класс; (2) requests ≤ limits.

## Проверка
```bash
kubectl -n lab apply -f manifests/resize/pod.yaml
kubectl -n lab wait --for=condition=Ready pod/resize-demo --timeout=60s

# ДО:
kubectl -n lab get pod resize-demo -o jsonpath='req={.spec.containers[0].resources.requests.cpu} restarts={.status.containerStatuses[0].restartCount}{"\n"}'

# КОРРЕКТНЫЙ resize: поднять И requests, И limits (Burstable сохраняется):
kubectl -n lab patch pod resize-demo --subresource resize --type=strategic \
  -p '{"spec":{"containers":[{"name":"app","resources":{"requests":{"cpu":"150m"},"limits":{"cpu":"300m"}}}]}}'

# ПОСЛЕ: req=150m, restarts=0 (CPU — NotRequired, без рестарта), allocatedResources обновился:
kubectl -n lab get pod resize-demo -o jsonpath='req={.spec.containers[0].resources.requests.cpu} restarts={.status.containerStatuses[0].restartCount} alloc={.status.containerStatuses[0].allocatedResources.cpu}{"\n"}'
```

## Эксперименты с ошибками (поймать валидацию)
```bash
# (а) поднять ТОЛЬКО requests.cpu до значения limit -> requests==limits -> QoS сменился бы:
#     "Pod QOS Class may not change as a result of resizing"
# (б) requests.cpu > limits.cpu -> "must be less than or equal to cpu limit"
# (в) resize памяти (resourceName memory у нас RestartContainer) -> контейнер РЕСТАРТНЕТ (restarts+1)
```

## Ожидаемый результат
CPU 100m→150m, `restarts=0`, `allocatedResources.cpu=150m`. Невалидные resize
отбиваются понятными ошибками (QoS / requests>limits).
