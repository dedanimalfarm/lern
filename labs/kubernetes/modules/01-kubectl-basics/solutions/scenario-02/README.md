# Решение сценария 02

**Причина.** readinessProbe проверяет `/healthz-typo`, которого у nginx нет (404); под никогда не становится Ready, Service не получает endpoints.

**Исправление.**
```bash
kubectl -n lab apply -f solutions/scenario-02/deploy.yaml
```

**Проверка.**
```bash
kubectl -n lab get pods -l app=kb-web     # 1/1 Running
kubectl -n lab get endpoints kb-web       # есть адрес
```
