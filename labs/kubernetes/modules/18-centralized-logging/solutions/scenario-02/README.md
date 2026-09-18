# Решение сценария 02

**Причина.** приложение перенаправило вывод в файл `/var/log/app.log` внутри контейнера — stdout пуст, CRI/Promtail/`kubectl logs` ничего не видят.

**Исправление.**
```bash
kubectl -n lab apply -f solutions/scenario-02/payment-api.yaml
```

**Проверка.**
```bash
kubectl -n lab logs deploy/payment-api --tail=3
```
