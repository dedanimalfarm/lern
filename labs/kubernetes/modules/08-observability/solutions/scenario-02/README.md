# Решение сценария 02

**Причина.** livenessProbe на несуществующий HTTP-эндпоинт с `failureThreshold: 1` — kubelet убивает здоровый контейнер каждые пару секунд (exit 137/143, «Liveness probe failed»).

**Исправление.**
```bash
kubectl -n lab apply -f solutions/scenario-02/deploy.yaml
```

**Проверка.**
```bash
kubectl -n lab get pods -l app=obs-demo   # RESTARTS не растёт минуту
```
