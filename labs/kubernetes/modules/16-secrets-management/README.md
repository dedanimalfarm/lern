# Лабораторная работа 16: Управление секретами (encryption-at-rest, Sealed Secrets, ESO, Vault dynamic)

> ⏱ время ~25 мин · сложность 3/5 · пререквизиты: Трек 1 и Трек 3

Цель: понять, почему обычный `Secret` — это НЕ безопасное хранение, и освоить
четыре прод-подхода: шифрование etcd (encryption-at-rest), **Sealed Secrets**
(git-safe), **External Secrets Operator** (синк из внешнего менеджера) и
**Vault + Vault Secrets Operator** с ДИНАМИЧЕСКИМИ секретами (креды генерируются
on-demand и ротируются). К концу модуля вы выбираете подход под задачу и видите
каждый вживую.

> Развитие модуля 07 (Secret/base64 — введение). ⚠️ Vault здесь в DEV-режиме —
> только для учёбы (in-memory, root-токен в открытую). Прод-Vault: HA, auto-unseal,
> audit.

---

## Предварительные требования

```bash
export KUBECONFIG=/root/.kube/kubespray.conf
kubectl create ns lab --dry-run=client -o yaml | kubectl apply -f -

## Стартовая проверка

Убедитесь, что кластер доступен:
```bash
kubectl get nodes
```

# Операторы модуля (ставятся по одному разу):
bash ../../scripts/bootstrap/08-install-sealed-secrets.sh          # Часть 2 (+ kubeseal CLI)
bash ../../scripts/bootstrap/09-install-external-secrets.sh        # Часть 3 (ESO, helm)
bash ../../scripts/bootstrap/10-install-vault-secrets-operator.sh  # Часть 4 (VSO, helm)
```

---

## Часть 1: Encryption-at-rest (как Secret лежит в etcd)

### Теория для изучения перед частью

- **`Secret` ≠ шифрование.** В etcd Secret хранится в **base64** (кодирование). Без
  включённого **encryption-at-rest** любой с доступом к etcd (или к бэкапу etcd)
  читает пароли открытым текстом.
- **EncryptionConfiguration** на apiserver (`--encryption-provider-config`)
  шифрует ресурсы (secrets) ПЕРЕД записью в etcd. Провайдеры: `aescbc`/`aesgcm`
  (ключ в конфиге), `kms` (внешний KMS — ключ НЕ в кластере, лучший вариант).

---

**Цель:** убедиться, шифруются ли secrets в etcd НА НАШЕМ кластере.

---

### 1.1 Прочитать Secret прямо из etcd

```bash
kubectl -n lab create secret generic etcd-probe --from-literal=password=SuperSecret123
CP=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' | sed -E 's#https://([0-9.]+):.*#\1#')

# На control-plane: читаем ключ /registry/secrets/lab/etcd-probe напрямую из etcd
ssh -i /root/.ssh/kubespray ubuntu@"$CP" 'sudo ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 --cacert=/etc/ssl/etcd/ssl/ca.pem \
  --cert=/etc/ssl/etcd/ssl/member-k8s-cp-1.pem --key=/etc/ssl/etcd/ssl/member-k8s-cp-1-key.pem \
  get /registry/secrets/lab/etcd-probe | strings | grep -iE "SuperSecret|k8s:enc"'
```

> ✅ **Прогнано на нашем Kubespray:** в etcd виден `"password":"U3VwZXJTZWNyZXQxMjM="`
> и даже строка `SuperSecret123` — **БЕЗ префикса `k8s:enc:`**, т.е.
> encryption-at-rest НЕ включён (`--encryption-provider-config` в apiserver не задан).
> Вывод: на этом кластере secrets в etcd — plaintext. Защита — RBAC на `secrets` +
> подходы Частей 2-4 + (в проде) включить EncryptionConfiguration.

> **Как включают (НЕ делаем на живом кластере — риск для control-plane):** кладут
> `EncryptionConfiguration` (provider aescbc/kms) на control-plane, добавляют
> apiserver-флаг `--encryption-provider-config=`, рестартят apiserver, затем
> `kubectl get secrets -A -o json | kubectl replace -f -` (перешифровать старые).

```bash
kubectl -n lab delete secret etcd-probe
```

**Контрольные вопросы:**
1. В каком виде Secret лежит в etcd по умолчанию?
2. Что делает EncryptionConfiguration и чем `kms`-провайдер лучше `aescbc`?
3. Почему RBAC на `secrets` — обязательная часть защиты, даже с шифрованием?

---

## Часть 2: Sealed Secrets (секреты, безопасные для git)

### Теория для изучения перед частью

- **Проблема GitOps:** Secret нельзя коммитить (base64 обратим). **Sealed Secrets**
  (Bitnami) решает: `kubeseal` шифрует Secret ПУБЛИЧНЫМ ключом контроллера →
  получается `SealedSecret`, который БЕЗОПАСНО коммитить. Расшифровать может ТОЛЬКО
  контроллер в кластере (приватный ключ у него).
- **SealedSecret привязан к КЛАСТЕРУ** (зашифрован его ключом) — на другом кластере
  не развернётся. Это by design (и одновременно — что проверять при «не
  расшифровывается»).

---

**Цель:** запечатать Secret и увидеть, как контроллер его разворачивает.

**Ресурс:** `manifests/sealed/sealed-secret.yaml` (сгенерирован kubeseal на ЭТОМ кластере).

---

### 2.1 Запечатать и развернуть

```bash
# Сгенерировать SealedSecret (исходный Secret НЕ коммитим):
kubectl -n lab create secret generic app-creds \
  --from-literal=username=appuser --from-literal=password='S3cr3tP@ss' \
  --dry-run=client -o yaml \
  | kubeseal --controller-namespace kube-system -o yaml > manifests/sealed/sealed-secret.yaml
grep -A2 encryptedData manifests/sealed/sealed-secret.yaml   # зашифрованные значения

# Применить SealedSecret -> контроллер создаёт обычный Secret app-creds
kubectl apply -f manifests/sealed/sealed-secret.yaml
kubectl -n lab get sealedsecret,secret app-creds
kubectl -n lab get secret app-creds -o jsonpath='{.data.password}' | base64 -d; echo   # S3cr3tP@ss
```

> ✅ **Прогнано:** `kubeseal` дал `SealedSecret` с `encryptedData` (RSA-шифр,
> безопасно для git); после `apply` контроллер создал `Secret/app-creds` с
> восстановленным `S3cr3tP@ss`. Закоммитить можно ИМЕННО SealedSecret.

**Контрольные вопросы:**
1. Чем `SealedSecret` безопаснее обычного Secret для git?
2. Кто и каким ключом расшифровывает SealedSecret?
3. Почему SealedSecret с одного кластера не развернётся на другом?

---

## Часть 3: External Secrets Operator (синк из внешнего менеджера)

### Теория для изучения перед частью

- **ESO** держит секреты ВО ВНЕШНЕМ менеджере (Vault/AWS Secrets Manager/GCP/…), а в
  кластер только СИНХРОНИЗИРУЕТ их в обычные Secret. В git — лишь ССЫЛКА (какой ключ
  откуда), самого секрета нет.
- **`SecretStore`** = описание источника (provider + доступ). **`ExternalSecret`** =
  что синхронизировать (какие ключи → в какой Secret) + `refreshInterval`.

---

**Цель:** синхронизировать секрет из источника в k8s Secret.

**Ресурс:** `manifests/eso/eso-fake.yaml` (provider `fake` — статика для демо).

---

### 3.1 SecretStore + ExternalSecret

```bash
kubectl -n lab apply -f manifests/eso/eso-fake.yaml
kubectl -n lab get externalsecret db-from-eso          # STATUS SecretSynced
kubectl -n lab get secret db-from-eso -o jsonpath='{.data.password}' | base64 -d; echo   # fake-pass-123
```

> ✅ **Прогнано:** ESO по `ExternalSecret` создал `Secret/db-from-eso` из источника
> (`fake-pass-123`). В проде вместо `fake` — провайдер Vault/AWS/GCP: секрет живёт
> там, ESO синхронит и обновляет по `refreshInterval`.

```bash
kubectl -n lab delete -f manifests/eso/eso-fake.yaml
```

**Контрольные вопросы:**
1. Что хранится в git при подходе ESO, а что — во внешнем менеджере?
2. Роли `SecretStore` и `ExternalSecret`?
3. Что даёт `refreshInterval`?

---

## Часть 4: Vault + динамические секреты (Vault Secrets Operator)

### Теория для изучения перед частью

- **Статический секрет** хранится (и может утечь). **Динамический секрет** Vault
  ГЕНЕРИРУЕТ on-demand с TTL: например, database-engine создаёт НОВОГО
  postgres-пользователя на каждый запрос и удаляет по истечении TTL. Утечь нечему —
  креды короткоживущие и уникальные.
- **Vault Secrets Operator (VSO)** синхронизирует Vault-секреты в k8s Secret. CRD:
  `VaultConnection` (адрес), `VaultAuth` (как логиниться — k8s ServiceAccount),
  **`VaultDynamicSecret`** (что генерировать) → кладёт результат в Secret и РОТИРУЕТ.

```
VaultDynamicSecret (VSO) --auth k8s SA--> Vault database-engine
        |                                      | CREATE ROLE ... (новый юзер + TTL)
        ▼                                      ▼
   k8s Secret pg-dynamic-creds  <----- свежие username/password каждые TTL ----- Postgres
```

---

**Цель:** получить динамические postgres-креды в k8s Secret через VSO.

**Ресурсы:** `manifests/vault/{vault-pg,rbac,setup-vault.sh,vso-secrets}.yaml`.

---

### 4.1 Развернуть Vault(dev)+Postgres и настроить

```bash
kubectl -n lab apply -f manifests/vault/vault-pg.yaml -f manifests/vault/rbac.yaml
kubectl -n lab rollout status deploy/vault --timeout=120s
kubectl -n lab rollout status deploy/pg --timeout=120s

# Настроить Vault: database-engine (динамические юзеры) + kubernetes-auth для VSO
bash manifests/vault/setup-vault.sh
```

### 4.2 Динамика: каждый запрос — НОВЫЙ пользователь

```bash
VPOD=$(kubectl -n lab get pod -l app=vault -o jsonpath='{.items[0].metadata.name}')
kubectl -n lab exec "$VPOD" -- sh -c 'VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root \
  vault read -field=username database/creds/dynrole'   # v-token-dynrole-XXXX
# повторите — username ДРУГОЙ (это и есть dynamic)
```

### 4.3 VSO кладёт динамические креды в k8s Secret

```bash
kubectl -n lab apply -f manifests/vault/vso-secrets.yaml
sleep 8
kubectl -n lab get secret pg-dynamic-creds -o jsonpath='{.data.username}' | base64 -d; echo
# v-kubernet-dynrole-XXXX   <- Vault-сгенерированный postgres-юзер, попал в Secret через VSO
```

> ✅ **Прогнано на Kubespray:** `vault read database/creds/dynrole` каждый раз даёт
> ДРУГОГО пользователя (`v-token-dynrole-sEUX…` ≠ `…jEMPlo…`); VSO через
> `VaultDynamicSecret` залогинился в Vault (k8s SA `vso-auth`) и положил динамические
> креды в `Secret/pg-dynamic-creds` (`v-kubernet-dynrole-…`). Креды нигде не хранятся
> постоянно — VSO ротирует их по TTL.

**Контрольные вопросы:**
1. Чем динамический секрет принципиально безопаснее статического?
2. Роли `VaultConnection`/`VaultAuth`/`VaultDynamicSecret` в VSO?
3. Как VSO аутентифицируется в Vault и зачем `system:auth-delegator`?

---

## Сравнение подходов

| Подход | Где живёт секрет | Git-safe? | Ротация | Когда |
|--------|------------------|-----------|---------|-------|
| обычный Secret | etcd (base64) | ❌ нет | нет | никогда не коммитить |
| encryption-at-rest | etcd (шифр) | — | нет | базовая защита etcd (всегда) |
| Sealed Secrets | git (шифр) + Secret | ✅ да | вручную | GitOps без внешнего менеджера |
| ESO | внешний менеджер | ✅ (ссылка) | по refresh | есть Vault/cloud-менеджер |
| Vault dynamic (VSO) | НЕ хранится (генерится) | ✅ | авто (TTL) | БД/облако, max безопасность |

---

## Проверка модуля

```bash
bash verify/verify.sh
# [OK] Sealed Secrets: SealedSecret -> Secret/app-creds расшифрован контроллером
# [OK] External Secrets Operator присутствует (CRD external-secrets.io)
# [OK] Vault Secrets Operator присутствует (CRD secrets.hashicorp.com)
# [OK] module 16 verified
```

`verify.sh`: применяет `SealedSecret` → контроллер создаёт `Secret/app-creds`
(детерминированное ядро) + проверяет наличие ESO и VSO (мягко). Части 1/4 —
интерактивные (SSH к etcd / Vault-стек).

---

## Финальная карта ресурсов модуля

| Ресурс | Часть | Что демонстрирует |
|--------|-------|-------------------|
| `etcd-probe` (Secret) | 1 | plaintext в etcd (encryption-at-rest off) |
| `app-creds` (SealedSecret→Secret) | 2 | git-safe секрет |
| `fake-store`+`db-from-eso` (ESO) | 3 | синк из внешнего менеджера |
| `vault`+`pg`+VSO CRs | 4 | динамические креды (генерируются on-demand) |
| `leaked-creds` (broken) | — | анти-паттерн: сырой Secret в git |

---

## Теоретические вопросы (итоговые)

1. Почему `Secret`/base64 — не защита? Что меняет encryption-at-rest?
2. Sealed Secrets: как делает git-safe и почему привязан к кластеру?
3. ESO: что в git, что во внешнем менеджере?
4. Динамические секреты Vault: в чём преимущество перед статическими?
5. Сравните 4 подхода: где живёт секрет, git-safe ли, ротация.

---

## Практические задания (отработка)

> Делайте на живом кластере; проверяйте себя командами и `verify/verify.sh`.

1. Прочитайте Secret прямо из etcd (etcdctl по SSH) и убедитесь, что он plaintext (нет `k8s:enc:`).
2. Запечатайте свой Secret через `kubeseal`, примените SealedSecret, проверьте созданный Secret; попробуйте применить его «на другом кластере» мысленно — почему не сработает?
3. ESO: смените значение в `SecretStore (fake)` и убедитесь, что синхронизированный Secret обновился по `refreshInterval`.
4. Vault: дважды прочитайте `database/creds/dynrole` и покажите, что пользователь КАЖДЫЙ раз новый.
5. VSO: удалите Secret `pg-dynamic-creds` руками и убедитесь, что оператор его восстановит.

---


## Чему вы научились

В этом модуле вы научились:
- Шифрованию секретов в etcd (encryption-at-rest)
- Использованию Sealed Secrets для хранения секретов в Git
- Интеграции с внешними хранилищами через External Secrets Operator

## Уборка

```bash
kubectl -n lab delete -f manifests/vault/vso-secrets.yaml --ignore-not-found
kubectl -n lab delete -f manifests/vault/vault-pg.yaml -f manifests/vault/rbac.yaml --ignore-not-found
kubectl -n lab delete sealedsecret app-creds --ignore-not-found
kubectl -n lab delete secret app-creds pg-dynamic-creds --ignore-not-found
kubectl delete clusterrolebinding vault-token-reviewer --ignore-not-found
# Операторы (sealed-secrets/ESO/VSO) — общие аддоны, ОСТАВЛЯЕМ.
```
