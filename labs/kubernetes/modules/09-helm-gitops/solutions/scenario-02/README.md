# Решение сценария 02

**Причина.** destination.namespace `prod` не входит в `spec.destinations` AppProject `labs` → `InvalidSpecError`, sync не начинается.

**Исправление.**
```bash
kubectl apply -f solutions/scenario-02/app.yaml
```

**Проверка.**
```bash
kubectl -n argocd get application demo-app-prod -o jsonpath='{.status.sync.status}/{.status.health.status}{"\n"}'   # Synced/Healthy
```
