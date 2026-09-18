# Решение сценария 02

**Причина.** в `ingress.from.podSelector` политики `api-policy` метка `app: frontend` вместо `app: web` — селектор пуст, правило ничего не разрешает.

**Исправление.**
```bash
kubectl -n lab apply -f solutions/scenario-02/api-policy.yaml
```

**Проверка.**
```bash
kubectl -n lab exec deploy/web -- wget -qO- -T 3 http://api | head -1
```
