# 01-microsegmentation

## Задача
Построить сегментацию web -> api -> db, где web НЕ может ходить в db напрямую.

## Команды
```bash
kubectl -n lab apply -f manifests/app.yaml
kubectl -n lab apply -f manifests/netpol/
kubectl -n lab get netpol
```

## Проверка
- web -> api: разрешено.
- web -> db: ЗАБЛОКИРОВАНО.
- api -> db: разрешено.
