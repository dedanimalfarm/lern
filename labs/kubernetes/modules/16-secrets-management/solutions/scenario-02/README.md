# Решение сценария 02

**Причина.** `remoteRef.key: /db/passwd` не существует в источнике → `SecretSyncedError`, целевой Secret не создаётся.

**Исправление.**
```bash
kubectl -n lab apply -f solutions/scenario-02/eso-typo.yaml
```

**Проверка.**
```bash
kubectl -n lab get externalsecret db-from-eso-v2   # SecretSynced / True
```
