# 02 — Scheduling gates (отложенный старт)

## Задача
Под с gate висит `SchedulingGated` (планировщик его игнорирует), пока gate не снят
патчем. Паттерн «жди approval/квоту/окно» без busy-wait в init.

## Проверка
```bash
kubectl -n lab apply -f manifests/gates/pod.yaml
kubectl -n lab get pod gated-demo
# gated-demo   0/1   Pending   ...     (reason=SchedulingGated)
kubectl -n lab get pod gated-demo -o jsonpath='{.status.conditions[0].reason}{"\n"}'   # SchedulingGated

# Снять gate можно ТОЛЬКО патчем (добавить новый — нельзя):
kubectl -n lab patch pod gated-demo --type=merge -p '{"spec":{"schedulingGates":[]}}'
sleep 5
kubectl -n lab get pod gated-demo                  # Running
```

## Ожидаемый результат
До патча — Pending/SchedulingGated; после снятия gate — Running.
