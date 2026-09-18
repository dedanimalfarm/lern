# 04 — Vault dynamic secrets через Vault Secrets Operator

## Задача
Получить от Vault динамические креды PostgreSQL, увидеть, что каждый запрос создаёт нового
пользователя с TTL, и что VSO кладёт их в k8s Secret и ротирует до истечения срока.

## Проверка
```bash
kubectl -n lab apply -f manifests/vault/vault-pg.yaml
kubectl -n lab rollout status deploy/vault deploy/pg --timeout=120s
bash manifests/vault/setup-vault.sh
VPOD=$(kubectl -n lab get pod -l app=vault -o jsonpath='{.items[0].metadata.name}')
for i in 1 2; do kubectl -n lab exec "$VPOD" -- sh -c 'VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root vault read -field=username database/creds/dynrole'; echo; done
kubectl -n lab apply -f manifests/vault/rbac.yaml -f manifests/vault/vso-secrets.yaml
sleep 10
kubectl -n lab get vaultdynamicsecret pg-dynamic
U1=$(kubectl -n lab get secret pg-dynamic-creds -o jsonpath='{.data.username}' | base64 -d); echo "$U1"
sleep 130
U2=$(kubectl -n lab get secret pg-dynamic-creds -o jsonpath='{.data.username}' | base64 -d); echo "$U2"
kubectl -n lab exec deploy/pg -- psql -U postgres -tAc "select usename from pg_user where usename like 'v-%';"
```

## Ожидаемый результат
- Два `vault read` подряд вернули двух **разных** пользователей `v-kubernet-dynrole-…` —
  Vault создаёт их в PostgreSQL на лету.
- `Secret/pg-dynamic-creds` появился; через ~2 минуты (TTL роли `2m`) `username` в нём
  изменился — VSO перевыпустил креды сам, приложение ничего не делало.
- В `pg_user` видны только живые динамические пользователи: истёкшие Vault отзывает.
- Вы объяснили, чем это безопаснее статического пароля в Secret (нет долгоживущего секрета,
  компрометация ограничена TTL) и что произойдёт с приложением, если Vault станет недоступен.
