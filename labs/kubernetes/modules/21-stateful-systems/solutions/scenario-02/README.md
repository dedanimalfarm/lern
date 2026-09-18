# Решение сценария 02

**Причина.** приложение пишет через `my-db-ro` (реплика, только чтение) — PostgreSQL отвечает `cannot execute ... in a read-only transaction`; для записи нужен `my-db-rw`.

**Исправление.**
```bash
kubectl -n lab apply -f solutions/scenario-02/db-writer.yaml
```

**Проверка.**
```bash
kubectl -n lab logs deploy/db-writer --tail=2   # inserted
```
