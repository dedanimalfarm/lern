# Решение сценария 02

**Причина.** `scaleTargetRef.name` указывает на несуществующий Deployment `hpa-demo-web` → `FailedGetScale`, `AbleToScale=False`, `<unknown>`.

**Исправление.**
```bash
kubectl -n lab apply -f solutions/scenario-02/hpa.yaml
```

**Проверка.**
```bash
kubectl -n lab get hpa hpa-demo   # TARGETS числом, REPLICAS >= 1
```
