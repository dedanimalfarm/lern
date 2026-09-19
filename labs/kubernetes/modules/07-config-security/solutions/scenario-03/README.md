# Решение сценария 03

**Причина.** образ `nginx:1.27-alpine` запускается от root и пишет в `/var/cache/nginx`, а политика требует `runAsNonRoot` и read-only rootfs — kubelet отказывается создавать контейнер (`CreateContainerConfigError`).

**Исправление.**
```bash
kubectl -n lab apply -f solutions/scenario-03/deploy.yaml
```

**Проверка.**
```bash
kubectl -n lab get pods -l app=hardened-web   # 1/1 Running
kubectl -n lab exec deploy/hardened-web -- id
```
