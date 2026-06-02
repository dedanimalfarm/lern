# 01-hpa-cpu

## Задача
Поднять Deployment с `requests.cpu` и HPA по CPU-утилизации.

## Команды
```bash
kubectl -n lab apply -f manifests/deploy.yaml -f manifests/svc.yaml -f manifests/hpa.yaml
kubectl -n lab get hpa hpa-demo
```

## Проверка
- TARGETS показывает реальный процент (например `0%/50%`), не `<unknown>`.
