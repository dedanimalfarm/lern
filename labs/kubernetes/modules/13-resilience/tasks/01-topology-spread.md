# 01-topology-spread

## Задача
Размазать реплики равномерно по нодам через topologySpreadConstraints.

## Команды
```bash
kubectl -n lab apply -f manifests/app.yaml
kubectl -n lab get pods -l app=resilient-app -o wide
```

## Проверка
- 3 реплики на 3 РАЗНЫХ нодах (колонка NODE).
- `maxSkew=1` не даёт перекоса; `DoNotSchedule` = жёстко.
