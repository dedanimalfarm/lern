#!/usr/bin/env bash
# Конфигурирует Vault (dev) для динамических postgres-кредов + kubernetes-auth для VSO.
# Запуск: bash setup-vault.sh   (нужен KUBECONFIG; Vault/pg уже развёрнуты vault-pg.yaml)
set -euo pipefail
VPOD=$(kubectl -n lab get pod -l app=vault -o jsonpath='{.items[0].metadata.name}')
kubectl -n lab exec "$VPOD" -- sh -c '
export VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root
# database secrets engine -> динамические пользователи postgres
vault secrets enable database >/dev/null 2>&1 || true
vault write database/config/appdb \
  plugin_name=postgresql-database-plugin allowed_roles=dynrole \
  connection_url="postgresql://{{username}}:{{password}}@pg.lab.svc:5432/appdb?sslmode=disable" \
  username=postgres password=rootpass >/dev/null
vault write database/roles/dynrole db_name=appdb \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '"'"'{{password}}'"'"' VALID UNTIL '"'"'{{expiration}}'"'"'; GRANT ALL PRIVILEGES ON DATABASE appdb TO \"{{name}}\";" \
  default_ttl=2m max_ttl=10m >/dev/null
# kubernetes auth -> VSO логинится SA lab:vso-auth
vault auth enable kubernetes >/dev/null 2>&1 || true
vault write auth/kubernetes/config kubernetes_host=https://kubernetes.default.svc \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
  token_reviewer_jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token >/dev/null
vault policy write dynrole-read - >/dev/null <<POL
path "database/creds/dynrole" { capabilities = ["read"] }
POL
vault write auth/kubernetes/role/dynrole-role \
  bound_service_account_names=vso-auth bound_service_account_namespaces=lab \
  policies=dynrole-read ttl=1h >/dev/null
echo "Vault настроен: database/roles/dynrole + kubernetes auth (role dynrole-role)"
'
