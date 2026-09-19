# Решение сценария 03

**Причина.** том смонтирован как `emptyDir` — он удаляется вместе с подом, поэтому каждая новая реплика начинает с пустого каталога; ошибок при этом нет, теряются только данные.

**Исправление.**
```bash
kubectl -n lab apply -f solutions/scenario-03/deploy.yaml
```

**Проверка.**
```bash
kubectl -n lab delete pod -l app=notes-app
kubectl -n lab logs deploy/notes-app | tail -1   # счётчик строк растёт
```
