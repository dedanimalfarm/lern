# Решение сценария 02

**Причина.** на объекте finalizer `lab.example.com/cleanup-external-dns`, а контроллера, который его снимает, нет → `deletionTimestamp` выставлен, удаление не завершается.

**Исправление.**
```bash
bash solutions/scenario-02/fix.sh
```

**Проверка.**
```bash
kubectl -n lab get webapp stuck-webapp   # NotFound
```
