# 07 · Secrets / HashiCorp Vault

> Тема из вакансии: «HashiCorp Vault (или аналог), безопасное хранение токенов, ключей, паролей»; «секреты, разграничение доступов, принцип least privilege».

## Цель и навыки

Понять, **почему нельзя класть секреты в git/env/`/etc/`**, и поднять Vault в dev-режиме, чтобы прочувствовать модель: auth method → token/identity → policy → secret engine → secret.

После лабы ты:

- объясняешь модель Vault словами «sealed/unsealed», «root token», «policy», «secret engine», «mount path», «lease/TTL»;
- умеешь работать с **KV v2** (versioned, soft-delete, undelete, destroy);
- пишешь HCL-policy на whitelist (`path "kv/data/lab/*" { capabilities = ["read"] }`);
- настраиваешь **AppRole** для машинной аутентификации (role-id + secret-id);
- понимаешь, **почему dev-mode никогда не идёт в прод** (in-memory, single unseal, root token в логи).

## Теоретический минимум

**Vault** — хранилище секретов с программируемым доступом. На старте `sealed`: данные в storage есть, но мастер-ключ не загружен. `Unseal` загружает мастер-ключ (5-of-3 Shamir по дефолту), после чего сервер обслуживает запросы. В dev-mode unseal делается автоматически, мастер-ключ и root-token — в stdout.

**Auth methods** — как пользователь/сервис себя представляет: `token`, `userpass`, `approle`, `aws`, `kubernetes`, `oidc`. Каждый method выдаёт **token** с привязанными policies.

**Secret engines** — что Vault умеет хранить или генерировать: `kv` (просто хранить), `database` (генерить временные креды для PG/MySQL), `pki` (выпускать сертификаты), `transit` (encrypt-as-a-service), `aws/gcp` (выпускать временные ключи).

**Policy** — HCL-описание прав на пути. По умолчанию **deny-all**, всё открывается явно.

**TTL и leases**: всё, что Vault выдаёт, имеет срок жизни. После expire — токен/секрет недействителен. Это и есть «короткоживущие creds» — золотой стандарт.

## Базовая отработка

### Шаг 1. Vault dev в Docker

```bash
docker run -d --name vault-dev \
  --cap-add=IPC_LOCK \
  -e VAULT_DEV_ROOT_TOKEN_ID=root \
  -e VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200 \
  -p 8200:8200 \
  hashicorp/vault:1.17

sleep 3
docker logs vault-dev 2>&1 | grep -E 'Unseal Key|Root Token|Listener' | head
```

Поставить CLI на хост:

```bash
sudo apt-get install -y gpg
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install -y vault

export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=root
vault status
```

`Sealed: false`, `Initialized: true` — ок.

### Шаг 2. KV v2 (versioned)

```bash
vault secrets enable -path=kv -version=2 kv
vault kv put kv/lab/db user=app password=initial-pw-please-change
vault kv get kv/lab/db
vault kv put kv/lab/db user=app password=rotated-pw-v2
vault kv get -version=1 kv/lab/db          # старая версия жива
vault kv metadata get kv/lab/db
vault kv delete kv/lab/db                  # soft-delete последней версии
vault kv undelete -versions=2 kv/lab/db
vault kv destroy -versions=1 kv/lab/db     # hard, без возврата
```

### Шаг 3. Policy + token с минимумом прав

```bash
cat > /tmp/lab-ro.hcl <<'EOF'
# Только read на kv/lab/*. Никакой list, никакой metadata.
path "kv/data/lab/*" {
  capabilities = ["read"]
}
EOF

vault policy write lab-ro /tmp/lab-ro.hcl
vault policy read lab-ro

readonly_token=$(vault token create -policy=lab-ro -ttl=1h -format=json | jq -r .auth.client_token)
echo "$readonly_token"

# проверка
VAULT_TOKEN=$readonly_token vault kv get kv/lab/db        # OK
VAULT_TOKEN=$readonly_token vault kv put kv/lab/db x=y    # permission denied — отлично
```

### Шаг 4. AppRole — машинный доступ

```bash
vault auth enable approle

vault write auth/approle/role/app-reader \
  token_policies="lab-ro" \
  token_ttl=15m \
  token_max_ttl=1h \
  secret_id_ttl=10m \
  bind_secret_id=true

ROLE_ID=$(vault read -format=json auth/approle/role/app-reader/role-id | jq -r .data.role_id)
SECRET_ID=$(vault write -force -format=json auth/approle/role/app-reader/secret-id | jq -r .data.secret_id)
echo "ROLE_ID=$ROLE_ID"
echo "SECRET_ID=$SECRET_ID"

# логинимся «как сервис»
APP_TOKEN=$(vault write -format=json auth/approle/login role_id="$ROLE_ID" secret_id="$SECRET_ID" | jq -r .auth.client_token)
VAULT_TOKEN=$APP_TOKEN vault kv get kv/lab/db
```

> Реальный паттерн: `ROLE_ID` зашит в Ansible-инвентарь/конфиг приложения (это **не** секрет, это идентификатор), `SECRET_ID` выпускается короткоживущим оператором (или systemd-таймером) и кладётся в файл, который сервис прочтёт **один раз** и удалит. Это и есть «secure introduction».

## Расширенная отработка

### Задача 1. Динамические creds для Postgres

Подними `postgres:16` рядом, включи `database` secret engine, настрой роль, которая выдаёт **временного юзера** Postgres с TTL=10m:

```bash
docker run -d --name pg -e POSTGRES_PASSWORD=pgpw -p 5432:5432 postgres:16

vault secrets enable database
vault write database/config/lab-pg \
  plugin_name=postgresql-database-plugin \
  allowed_roles="readonly" \
  connection_url="postgresql://{{username}}:{{password}}@host.docker.internal:5432/postgres?sslmode=disable" \
  username="postgres" password="pgpw"

vault write database/roles/readonly \
  db_name=lab-pg \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT pg_read_all_data TO \"{{name}}\";" \
  default_ttl=10m max_ttl=1h

vault read database/creds/readonly        # ← каждый вызов = новый пользователь Postgres
```

Проверь, что юзер живой, потом — что после revoke он удалён:

```bash
lease_id=$(vault read -format=json database/creds/readonly | jq -r .lease_id)
vault lease revoke "$lease_id"
docker exec -i pg psql -U postgres -c '\du' | grep v-
```

Это — **«golden path» Vault**, его обычно показывают на собесе.

### Задача 2. Минимальный wrapper в Ansible

Сделай `lookup('community.hashi_vault.vault_kv2_get', 'lab/db', token=approle_token, url=VAULT_ADDR)` в playbook'е, который кладёт пароль в шаблонную конфигурацию приложения. Контракт: **пароль не должен попасть в git, ни в чистом виде, ни в зашифрованном виде из ansible-vault** — это альтернатива (но и более «правильно» в проде).

### Задача 3. Что сломается, если потерять unseal-keys

Останови контейнер, запусти **не**-dev режим (`vault server -config=...`) с file storage. Initialize → получи 5 unseal-keys и root. Запиши только 2. Восстанови сервер — он **запечатан**, и расшифровать его нечем. Это и есть DR-сценарий: «храни 3 из 5 unseal-shards в разных физических местах + root-token в HSM/SealedSecret/safe».

## Acceptance criteria

- [ ] `vault status` показывает `Sealed: false`.
- [ ] `kv/lab/db` имеет ≥2 версии (после put дважды).
- [ ] Под токеном с policy `lab-ro` read работает, write — `permission denied`.
- [ ] AppRole-login выдаёт токен с TTL ≤ 1h.
- [ ] (Расширенная) `vault read database/creds/readonly` создаёт реального юзера Postgres, после `lease revoke` юзер исчезает.

## Что обсудить на ревью

1. Что такое `sealed/unsealed` и почему дев-режим — `auto-unsealed`?
2. Почему `ROLE_ID` — не секрет, а `SECRET_ID` — секрет?
3. Где живут leases и что произойдёт, если **все** ноды Vault упадут одновременно?
4. Чем `kv v2` отличается от `kv v1`?
5. Когда Vault — не нужен? (Подсказка: cloud KMS + IAM роль может быть проще для одного облака.)
6. Что такое **secrets sprawl** и как мы его лечим?

## Как погасить

```bash
docker rm -f vault-dev pg 2>/dev/null
unset VAULT_TOKEN VAULT_ADDR
```

## Грабли

| Симптом | Причина | Лечение |
|---------|---------|---------|
| `Vault is sealed` | реальный (не dev) сервер после рестарта | `vault operator unseal <key>` по 3 раза |
| `permission denied` на читаемый секрет | путь kv v2 в policy — `kv/data/...`, не `kv/...` | смотри `vault kv get -output-curl-string ...` |
| AppRole `bind_secret_id` неучтён | роль создана без него | пересоздай с `bind_secret_id=true` |
| Vault CLI не видит сервер | забыл `export VAULT_ADDR` | `export VAULT_ADDR=http://127.0.0.1:8200` |
| `connection refused` к pg из Vault-контейнера | `host.docker.internal` не настроен | `--add-host=host.docker.internal:host-gateway` контейнеру vault |
