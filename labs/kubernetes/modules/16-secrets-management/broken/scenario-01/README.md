# Инцидент: пароль «утёк» через обычный Secret в git

`broken/scenario-01/plain-secret.yaml` — обычный k8s Secret с `data.password` в base64.

## Проблема
base64 — КОДИРОВАНИЕ, не шифрование. Любой с доступом к репо (или к etcd, см. Часть 1)
читает пароль одной командой:
```bash
echo 'U3VwZXJTZWNyZXQxMjM=' | base64 -d      # -> SuperSecret123
```
Коммитить сырой Secret в git = опубликовать секрет.

## Решение
НЕ коммитить сырые Secret. Подходы модуля:
- **SealedSecret** (`solutions/01-sealed/`) — зашифровано ключом кластера, git-safe;
- **ExternalSecret** (ESO) — секрет во внешнем менеджере, в git только ссылка;
- **VaultDynamicSecret** (VSO) — креды не хранятся, генерируются on-demand.
