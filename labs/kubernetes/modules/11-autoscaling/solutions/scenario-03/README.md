# Решение сценария 03

**Причина.** агрессивная livenessProbe держит поды в рестартах, Ready-подов нет, а HPA собирает метрики только с Ready — отсюда `<unknown>` при живом metrics-server и заданных requests.

**Исправление.**
```bash
kubectl -n lab apply -f solutions/scenario-03/deploy.yaml
```

**Проверка.**
```bash
kubectl -n lab get hpa hpa-demo   # TARGETS числом
```
