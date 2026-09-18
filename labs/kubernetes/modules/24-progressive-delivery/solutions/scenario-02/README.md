# Решение сценария 02

**Причина.** `spec.strategy.canary.canaryService` ссылается на несуществующий Service → `InvalidSpec`, Rollout `Degraded`, выкатка не стартует.

**Исправление.**
```bash
kubectl -n lab apply -f solutions/scenario-02/rollout.yaml
```

**Проверка.**
```bash
kubectl argo rollouts -n lab get rollout demo-rollout | head -3
```
