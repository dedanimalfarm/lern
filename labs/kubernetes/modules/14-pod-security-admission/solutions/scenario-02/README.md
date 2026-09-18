# Решение сценария 02

**Причина.** VAP `no-latest-tag` проверяет поды: Deployment с `nginx:latest` создаётся, а ReplicaSet получает Deny при создании пода (`ReplicaFailure`, Events RS).

**Исправление.**
```bash
kubectl -n lab apply -f solutions/scenario-02/deploy.yaml
```

**Проверка.**
```bash
kubectl -n lab get pods -l app=latest-app   # 1/1 Running
```
