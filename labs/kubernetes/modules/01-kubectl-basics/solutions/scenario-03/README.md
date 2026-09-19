# Решение сценария 03

**Причина.** `limits.memory: 8Mi` меньше, чем нужно nginx: ядро убивает контейнер (`OOMKilled`, exit 137), kubelet перезапускает его по кругу.

**Исправление.**
```bash
kubectl -n lab apply -f solutions/scenario-03/deploy.yaml
```

**Проверка.**
```bash
kubectl -n lab get pods -l app=kb-web   # Running, RESTARTS стабильны
```
