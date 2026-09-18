# Решение сценария 02

**Причина.** `spec.sourceRepos` AppProject `labs-gitops` не содержит репозиторий, из которого ApplicationSet генерирует Application → `InvalidSpecError` у всех трёх окружений.

**Исправление.**
```bash
kubectl apply -f solutions/scenario-02/appproject.yaml
```

**Проверка.**
```bash
kubectl -n argocd get applications   # все Synced
```
