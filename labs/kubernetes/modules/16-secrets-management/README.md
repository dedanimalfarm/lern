# Лабораторная работа 16: Управление секретами в Kubernetes (encryption-at-rest, Sealed Secrets, ESO, Vault dynamic)

## Оглавление
<!-- TOC -->
- [Предварительные требования](#предварительные-требования)
- [Стартовая проверка](#стартовая-проверка)
- [Часть 1: Encryption-at-rest (как Secret лежит в etcd)](#часть-1-encryption-at-rest-как-secret-лежит-в-etcd)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью)
  - [1.1 Прочитать Secret прямо из etcd](#11-прочитать-secret-прямо-из-etcd)
  - [1.2 Архитектура EncryptionConfiguration](#12-архитектура-encryptionconfiguration)
- [Часть 2: Sealed Secrets (секреты, безопасные для git)](#часть-2-sealed-secrets-секреты-безопасные-для-git)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-1)
  - [2.1 Установка и проверка Sealed Secrets](#21-установка-и-проверка-sealed-secrets)
  - [2.2 Запечатывание и развертывание SealedSecret](#22-запечатывание-и-развертывание-sealedsecret)
  - [2.3 Ротация ключей контроллера](#23-ротация-ключей-контроллера)
- [Часть 3: External Secrets Operator (синк из внешнего менеджера)](#часть-3-external-secrets-operator-синк-из-внешнего-менеджера)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-2)
  - [3.1 Настройка SecretStore + ExternalSecret](#31-настройка-secretstore--externalsecret)
  - [3.2 Ротация и refreshInterval](#32-ротация-и-refreshinterval)
- [Часть 4: Vault + динамические секреты (Vault Secrets Operator)](#часть-4-vault--динамические-секреты-vault-secrets-operator)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-3)
  - [4.1 Развернуть Vault(dev)+Postgres и настроить](#41-развернуть-vaultdevpostgres-и-настроить)
  - [4.2 Динамика: каждый запрос — НОВЫЙ пользователь](#42-динамика-каждый-запрос--новый-пользователь)
  - [4.3 VSO кладёт динамические креды в k8s Secret](#43-vso-кладёт-динамические-креды-в-k8s-secret)
- [Сравнение подходов](#сравнение-подходов)
- [Troubleshooting — частые проблемы и боевые инциденты](#troubleshooting--частые-проблемы-и-боевые-инциденты)
- [Проверка модуля](#проверка-модуля)
- [Финальная карта ресурсов модуля](#финальная-карта-ресурсов-модуля)
- [Контрольные вопросы](#контрольные-вопросы)
- [Практические задания (отработка)](#практические-задания-отработка)
- [Чему вы научились](#чему-вы-научились)
- [Уборка](#уборка)
- [Шпаргалка](#шпаргалка)
<!-- /TOC -->

> ⏱ время ~35-45 мин · сложность 3/5 · пререквизиты: Трек 1 и Трек 3

Цель всей работы: понять, почему обычный `Secret` — это НЕ безопасное хранение, и глубоко освоить
четыре production-подхода: шифрование etcd (encryption-at-rest), **Sealed Secrets**
(git-safe), **External Secrets Operator** (синк из внешнего менеджера) и
**Vault + Vault Secrets Operator** с ДИНАМИЧЕСКИМИ секретами (креды генерируются
on-demand и ротируются). К концу модуля вы научитесь выбирать подходящий инструмент под ваши задачи и диагностировать типовые проблемы, связанные с доступом к секретам.

> Развитие модуля 07 (Secret/base64 — введение). ⚠️ Vault здесь в DEV-режиме —
> только для учёбы (in-memory, root-токен в открытую). Прод-Vault: HA, auto-unseal, audit.

---

## Предварительные требования

Для начала работы необходимо убедиться, что окружение готово и все нужные контроллеры будут установлены.

```bash
# Устанавливаем KUBECONFIG для нашего Kubespray-стенда
export KUBECONFIG=/root/.kube/kubespray.conf

# Создаем namespace для лабораторной работы
kubectl create ns lab --dry-run=client -o yaml | kubectl apply -f -

# Удобный алиас
alias k='kubectl -n lab'
```

### Стартовая проверка

Убедитесь, что кластер доступен и ноды находятся в статусе Ready:
```bash
kubectl get nodes -o wide
```

```
NAME     STATUS   ROLES           AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION     CONTAINER-RUNTIME
k8s-cp   Ready    control-plane   10d   v1.27.1   10.0.0.10     <none>        Ubuntu 22.04.2 LTS   5.15.0-72-generic  containerd://1.7.0
```

Установите операторы, необходимые для модуля. Эти скрипты устанавливают соответствующие Helm-чарты. (Ставятся по одному разу на кластер):
```bash
bash ../../scripts/bootstrap/08-install-sealed-secrets.sh          # Часть 2 (+ kubeseal CLI)
bash ../../scripts/bootstrap/09-install-external-secrets.sh        # Часть 3 (ESO, helm)
bash ../../scripts/bootstrap/10-install-vault-secrets-operator.sh  # Часть 4 (VSO, helm)
```

Проверьте, что все поды операторов поднялись и находятся в статусе `Running`:
```bash
kubectl get pods -A | grep -E "sealed-secrets|external-secrets|vault-secrets"
```

---

## Часть 1: Encryption-at-rest (как Secret лежит в etcd)

### Теория для изучения перед частью

Многие инженеры ошибочно считают, что ресурс `Secret` в Kubernetes надежно зашифрован. Однако:
- **`Secret` ≠ шифрование.** В etcd ресурсы типа Secret хранятся закодированными в **base64** (кодирование, а не шифрование). Base64 легко обратим любой стандартной утилитой.
- Без включённого **encryption-at-rest** любой пользователь с прямым доступом к etcd (или к его бэкапу) может прочитать пароли, токены и сертификаты открытым текстом.
- В Kubernetes существует механизм **EncryptionConfiguration**. Он настраивается на уровне `kube-apiserver` (через флаг `--encryption-provider-config`).
- Когда `kube-apiserver` записывает `Secret` в etcd, он прогоняет его через указанный в конфигурации провайдер (например, `aescbc`, `aesgcm` или внешний `kms`). При чтении — расшифровывает.

**Доступные провайдеры шифрования:**
1. `identity` — без шифрования (по умолчанию).
2. `aescbc` / `aesgcm` / `secretbox` — ключи шифрования хранятся прямо в конфиге на control-plane нодах. Улучшает безопасность бэкапов, но если злоумышленник получит доступ к ФС control-plane, он получит и ключи.
3. `kms` (v1/v2) — использование внешнего Key Management Service (AWS KMS, Azure Key Vault, HashiCorp Vault). Ключи не хранятся в кластере. Это **industry standard** для production-инсталляций.

---

**Цель:** убедиться, шифруются ли secrets в etcd НА НАШЕМ кластере по умолчанию.

---

### 1.1 Прочитать Secret прямо из etcd

Создадим тестовый секрет в нашем namespace `lab`.

```bash
kubectl -n lab create secret generic etcd-probe --from-literal=password=SuperSecret123
```

Определим IP-адрес нашей Control Plane ноды, на которой запущен etcd:
```bash
CP=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' | sed -E 's#https://([0-9.]+):.*#\1#')
echo "Control plane IP: $CP"
```

Теперь подключимся к control-plane по SSH и прочитаем ключ `/registry/secrets/lab/etcd-probe` напрямую из etcd, используя сертификаты etcd.

```bash
# На control-plane: читаем ключ /registry/secrets/lab/etcd-probe напрямую из etcd
ssh -i /root/.ssh/kubespray ubuntu@"$CP" 'sudo ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 --cacert=/etc/ssl/etcd/ssl/ca.pem \
  --cert=/etc/ssl/etcd/ssl/member-k8s-cp-1.pem --key=/etc/ssl/etcd/ssl/member-k8s-cp-1-key.pem \
  get /registry/secrets/lab/etcd-probe | strings | grep -iE "SuperSecret|k8s:enc"'
```

> ✅ **Прогнано на нашем Kubespray:** в выводе виден `"password":"U3VwZXJTZWNyZXQxMjM="` (base64)
> и даже строка `SuperSecret123` открытым текстом — **БЕЗ префикса `k8s:enc:`**.
> Это означает, что encryption-at-rest НЕ включён (`--encryption-provider-config` в apiserver не задан).
> Вывод: на этом кластере secrets в etcd — plaintext. Защита базируется только на строгом RBAC-доступе к ресурсам `secrets`.

### 1.2 Архитектура EncryptionConfiguration

> **Как включают шифрование (НЕ делаем на живом кластере в этой лабе — риск для control-plane):**

1. Кладут `EncryptionConfiguration` на все control-plane ноды (например, в `/etc/kubernetes/pki/etcd-encryption.yaml`):
```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: <BASE64_ENCODED_KEY>
      - identity: {}
```
2. Добавляют apiserver-флаг `--encryption-provider-config=/etc/kubernetes/pki/etcd-encryption.yaml`.
3. Рестартят apiserver (например, удаляя статический Pod `kube-apiserver`).
4. После включения новые секреты будут шифроваться, но старые останутся plaintext. Чтобы перешифровать все старые секреты, нужно выполнить:
```bash
kubectl get secrets -A -o json | kubectl replace -f -
```

Удалим тестовый секрет:
```bash
kubectl -n lab delete secret etcd-probe
```

---

## Часть 2: Sealed Secrets (секреты, безопасные для git)

### Теория для изучения перед частью

- **Проблема GitOps:** Парадигма GitOps требует, чтобы вся конфигурация хранилась в Git (как single source of truth). Но обычный `Secret` нельзя коммитить, так как base64 обратим.
- **Sealed Secrets** от Bitnami решает эту проблему асимметричным шифрованием. В кластере устанавливается контроллер, который генерирует пару ключей (public/private).
- Утилита `kubeseal` (у разработчика локально) берет публичный ключ из кластера и шифрует ваш `Secret`. Получается CRD `SealedSecret`, который содержит только зашифрованный блоб (`encryptedData`).
- `SealedSecret` БЕЗОПАСНО коммитить в публичный репозиторий.
- При применении `SealedSecret` в кластер (`kubectl apply`), контроллер читает его, расшифровывает с помощью приватного ключа и прозрачно создает обычный `Secret`, который уже могут использовать приложения.
- **Ограничение (by design):** `SealedSecret` криптографически привязан к конкретному кластеру и namespace. Если вы попытаетесь развернуть его на другом кластере (с другим ключом) или даже в другом namespace, расшифровка завершится с ошибкой.

---

**Цель:** запечатать Secret локально и увидеть, как контроллер автоматически разворачивает его в кластере.

**Ресурс:** `manifests/sealed/sealed-secret.yaml` (мы сгенерируем его прямо сейчас).

---

### 2.1 Установка и проверка Sealed Secrets

Мы уже установили контроллер с помощью скрипта. Давайте проверим его статус:

```bash
kubectl -n kube-system get pods -l name=sealed-secrets-controller
```

Контроллер хранит свой приватный ключ в виде обычного секрета в `kube-system`:
```bash
kubectl -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key
```
> ⚠️ **Важно для DR (Disaster Recovery):** Этот секрет (ключ) — это то, что нужно обязательно бэкапить. Если вы потеряете кластер и этот ключ, вы больше никогда не сможете расшифровать ваши `SealedSecret` из Git.

### 2.2 Запечатывание и развертывание SealedSecret

Сгенерируем обычный `Secret`, но не будем его сохранять (используем `--dry-run=client`), а сразу передадим в `kubeseal`.

```bash
# Создаем директорию для манифестов, если её нет
mkdir -p manifests/sealed

# Сгенерировать SealedSecret (исходный Secret НЕ коммитим):
kubectl -n lab create secret generic app-creds \
  --from-literal=username=appuser --from-literal=password='S3cr3tP@ss' \
  --dry-run=client -o yaml \
  | kubeseal --controller-namespace kube-system -o yaml > manifests/sealed/sealed-secret.yaml

# Посмотрим, как выглядит зашифрованный файл:
cat manifests/sealed/sealed-secret.yaml | grep -A5 encryptedData
```

```yaml
  encryptedData:
    password: AgB6...<long_base64_string>...
    username: AgB6...<long_base64_string>...
```

Как видите, значения надежно зашифрованы. Этот файл `sealed-secret.yaml` мы можем смело делать `git add` и `git push`.

### 2.3 Ротация ключей контроллера

Применим SealedSecret в кластер:
```bash
# Применить SealedSecret -> контроллер создает обычный Secret app-creds
kubectl apply -f manifests/sealed/sealed-secret.yaml

# Проверим, что создались оба ресурса
kubectl -n lab get sealedsecret,secret app-creds
```

```
NAME                                   AGE
sealedsecret.bitnami.com/app-creds     10s

NAME               TYPE     DATA   AGE
secret/app-creds   Opaque   2      9s
```

Проверим, что внутри `Secret` лежат правильные, расшифрованные данные:
```bash
kubectl -n lab get secret app-creds -o jsonpath='{.data.password}' | base64 -d; echo
# Ожидаемый вывод: S3cr3tP@ss
```

> ✅ **Прогнано:** `kubeseal` дал `SealedSecret` с `encryptedData` (RSA-шифр,
> безопасно для git); после `apply` контроллер успешно создал `Secret/app-creds` с
> восстановленным `S3cr3tP@ss`.

Что будет, если контроллер обновит свои ключи (key rotation)? По умолчанию Sealed Secrets создает новый ключ каждые 30 дней. Новые SealedSecrets будут шифроваться новым публичным ключом. Однако контроллер хранит старые ключи, поэтому старые манифесты продолжат успешно расшифровываться.

---

## Часть 3: External Secrets Operator (синк из внешнего менеджера)

### Теория для изучения перед частью

Sealed Secrets хорош, но имеет недостатки:
- Нужно использовать CLI `kubeseal` при каждом изменении секрета разработчиком.
- Разработчик должен знать секрет, чтобы его зашифровать.
- Ротация паролей в БД не приведет к автоматическому обновлению SealedSecret в Git.

- **External Secrets Operator (ESO)** решает задачу иначе: он держит секреты ВО ВНЕШНЕМ менеджере (Vault, AWS Secrets Manager, GCP Secret Manager, Azure Key Vault), а в Kubernetes-кластер только СИНХРОНИЗИРУЕТ их в обычные `Secret`.
- В Git-репозитории при этом хранится лишь **ССЫЛКА** (CRD `ExternalSecret` — инструкция, какой ключ откуда забрать), самого секрета в Git нет вообще.

**Основные CRD оператора ESO:**
1. **`SecretStore`** (namespace-scoped) или **`ClusterSecretStore`** (cluster-scoped) = описание источника. Содержит информацию о провайдере (например, URL Vault'а) и том, как к нему аутентифицироваться.
2. **`ExternalSecret`** = инструкция, что конкретно синхронизировать (какие ключи взять из SecretStore и как назвать итоговый `Secret` в Kubernetes). Также задает `refreshInterval` для ротации.

---

**Цель:** синхронизировать секрет из внешнего источника в k8s Secret и проверить его обновление.

**Ресурс:** `manifests/eso/eso-fake.yaml` (мы используем provider `fake` — специальный статический провайдер в памяти для демо-целей, чтобы не настраивать реальный облачный аккаунт).

---

### 3.1 Настройка SecretStore + ExternalSecret

Создадим директорию и манифест:
```bash
mkdir -p manifests/eso

cat << 'EOF' > manifests/eso/eso-fake.yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: fake-store
  namespace: lab
spec:
  provider:
    fake:
      data:
        - key: my-database-password
          version: v1
          valueMap:
            password: fake-pass-123
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-from-eso
  namespace: lab
spec:
  refreshInterval: "10s"           # Как часто проверять обновления в источнике
  secretStoreRef:
    name: fake-store               # Ссылка на наш SecretStore
    kind: SecretStore
  target:
    name: db-from-eso              # Имя создаваемого k8s Secret
    creationPolicy: Owner
  data:
  - secretKey: password            # Ключ внутри итогового k8s Secret
    remoteRef:
      key: my-database-password    # Ключ во внешнем провайдере
      property: password           # Поле внутри внешнего ключа
EOF
```

Применим манифесты:
```bash
kubectl -n lab apply -f manifests/eso/eso-fake.yaml
```

Проверим статус `ExternalSecret`:
```bash
kubectl -n lab get externalsecret db-from-eso
```

```
NAME          STORE        REFRESH INTERVAL   STATUS         READY
db-from-eso   fake-store   10s                SecretSynced   True
```

Статус `SecretSynced` означает, что ESO успешно сходил в "провайдер", достал данные и создал Secret.
Проверим сам Secret:
```bash
kubectl -n lab get secret db-from-eso -o jsonpath='{.data.password}' | base64 -d; echo
# Ожидаемый вывод: fake-pass-123
```

### 3.2 Ротация и refreshInterval

Одно из мощных свойств ESO — это периодическая синхронизация (`refreshInterval: "10s"`).
Сымитируем изменение пароля администратором во внешнем менеджере (изменим `fake-store`):

```bash
kubectl -n lab patch secretstore fake-store --type=merge -p '{"spec":{"provider":{"fake":{"data":[{"key":"my-database-password","version":"v2","valueMap":{"password":"new-strong-pass"}}]}}}}'
```

Теперь ESO через несколько секунд заметит изменение (по таймеру refreshInterval) и обновит k8s Secret:

```bash
sleep 15
kubectl -n lab get secret db-from-eso -o jsonpath='{.data.password}' | base64 -d; echo
# Ожидаемый вывод: new-strong-pass
```

> ✅ **Прогнано:** В проде вместо `fake` используется провайдер Vault/AWS/GCP: секрет физически живёт там. ESO синхронит и обновляет его. Ваше приложение просто монтирует обычный `Secret/db-from-eso` как volume или env, не зная ничего про ESO или AWS.

Очистим ресурсы:
```bash
kubectl -n lab delete -f manifests/eso/eso-fake.yaml
```

---

## Часть 4: Vault + динамические секреты (Vault Secrets Operator)

### Теория для изучения перед частью

- **Статический секрет** — это пароль, который кто-то сгенерировал, положил в Vault, и он хранится там месяцами. Он может утечь, его нужно вручную менять.
- **Динамический секрет** — это магия Vault. Vault не хранит пароль. Вместо этого он генерирует новые уникальные учетные данные on-demand с заданным Time-To-Live (TTL). Например, database-engine Vault'а подключается к PostgreSQL как superuser, создаёт НОВОГО postgres-пользователя (вида `v-token-dynrole-Xj8...`) и выдает этот логин/пароль клиенту. По истечении TTL Vault сам делает `DROP ROLE` в базе.
- Утечь нечему — креды короткоживущие, уникальные для каждого приложения, и они уничтожаются автоматически.
- **Vault Secrets Operator (VSO)** от HashiCorp синхронизирует Vault-секреты (как статические, так и динамические) в k8s Secret.

**CRD VSO:**
- `VaultConnection` (адрес Vault сервера)
- `VaultAuth` (как VSO должен аутентифицироваться в Vault — мы используем Kubernetes ServiceAccount)
- **`VaultDynamicSecret`** (какую динамическую роль запросить) → VSO запрашивает креды у Vault, кладёт результат в Kubernetes Secret и РОТИРУЕТ их до истечения TTL (обычно на 2/3 срока жизни), автоматически обновляя k8s Secret.

**Схема работы:**
```
VaultDynamicSecret (VSO) --auth k8s SA--> Vault database-engine
        |                                      | CREATE ROLE (новый юзер + TTL)
        ▼                                      ▼
   k8s Secret pg-dynamic-creds  <----- свежие username/password ----- Postgres
```

---

**Цель:** получить динамические postgres-креды в k8s Secret через VSO и увидеть ротацию.

---

### 4.1 Развернуть Vault(dev)+Postgres и настроить

Создадим директорию и манифесты:
```bash
mkdir -p manifests/vault
```

> Для экономии места в README мы создаем ресурсы через bash heredoc:

```bash
cat << 'EOF' > manifests/vault/vault-pg.yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: vault, namespace: lab }
spec:
  selector: { matchLabels: { app: vault } }
  template:
    metadata: { labels: { app: vault } }
    spec:
      containers:
      - name: vault
        image: hashicorp/vault:1.14.1
        env:
        - { name: VAULT_DEV_ROOT_TOKEN_ID, value: "root" }
        - { name: VAULT_DEV_LISTEN_ADDRESS, value: "0.0.0.0:8200" }
        ports: [{ containerPort: 8200 }]
---
apiVersion: v1
kind: Service
metadata: { name: vault, namespace: lab }
spec:
  selector: { app: vault }
  ports: [{ port: 8200 }]
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: pg, namespace: lab }
spec:
  selector: { matchLabels: { app: pg } }
  template:
    metadata: { labels: { app: pg } }
    spec:
      containers:
      - name: pg
        image: postgres:15-alpine
        env:
        - { name: POSTGRES_PASSWORD, value: "rootpass" }
        ports: [{ containerPort: 5432 }]
---
apiVersion: v1
kind: Service
metadata: { name: pg, namespace: lab }
spec:
  selector: { app: pg }
  ports: [{ port: 5432 }]
EOF
```

```bash
# Разворачиваем Vault и Postgres
kubectl -n lab apply -f manifests/vault/vault-pg.yaml
kubectl -n lab rollout status deploy/vault --timeout=120s
kubectl -n lab rollout status deploy/pg --timeout=120s
```

Настроим Vault. Нам нужно:
1. Включить Kubernetes Auth (чтобы VSO мог авторизоваться через ServiceAccount `vso-auth`).
2. Включить Database Engine, подключить его к нашему Postgres.
3. Создать динамическую роль `dynrole` с SQL-шаблоном `CREATE ROLE...` и TTL=1m.

```bash
cat << 'EOF' > manifests/vault/setup-vault.sh
VPOD=$(kubectl -n lab get pod -l app=vault -o jsonpath='{.items[0].metadata.name}')

kubectl -n lab exec "$VPOD" -- sh -c '
VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root

# Включаем Kubernetes Auth
vault auth enable kubernetes
vault write auth/kubernetes/config \
  kubernetes_host="https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT"

# Политика для VSO: разрешаем чтение динамических кредов
vault policy write vso-policy - << EOP
path "database/creds/dynrole" { capabilities = ["read"] }
EOP

# Привязываем ServiceAccount vso-auth к роли и политике
vault write auth/kubernetes/role/vso-role \
  bound_service_account_names=vso-auth \
  bound_service_account_namespaces=lab \
  policies=vso-policy \
  ttl=1h

# Настраиваем Database Engine
vault secrets enable database
vault write database/config/my-pg \
  plugin_name=postgresql-database-plugin \
  allowed_roles="dynrole" \
  connection_url="postgresql://postgres:rootpass@pg.lab.svc.cluster.local:5432/postgres?sslmode=disable"

# Создаем роль для генерации кредов с коротким TTL (1 минута)
vault write database/roles/dynrole \
  db_name=my-pg \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '\''{{password}}'\'' VALID UNTIL '\''{{expiration}}'\''; GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
  default_ttl="1m" \
  max_ttl="5m"
'
EOF

bash manifests/vault/setup-vault.sh
```

Чтобы Vault Auth через Kubernetes работал, нам нужно дать ServiceAccount'у VSO права `system:auth-delegator`, чтобы он мог вызывать TokenReview API для проверки токенов.

```bash
cat << 'EOF' > manifests/vault/rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vso-auth
  namespace: lab
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: role-tokenreview-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
- kind: ServiceAccount
  name: vso-auth
  namespace: lab
EOF
kubectl -n lab apply -f manifests/vault/rbac.yaml
```

### 4.2 Динамика: каждый запрос — НОВЫЙ пользователь

Проверим логику динамических секретов прямо в Vault:

```bash
VPOD=$(kubectl -n lab get pod -l app=vault -o jsonpath='{.items[0].metadata.name}')
kubectl -n lab exec "$VPOD" -- sh -c 'VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root \
  vault read -field=username database/creds/dynrole'
# Вывод: v-root-dynrole-XXXXXX

# Вызовем еще раз:
kubectl -n lab exec "$VPOD" -- sh -c 'VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root \
  vault read -field=username database/creds/dynrole'
# Вывод: v-root-dynrole-YYYYYY  (Совершенно новый пользователь!)
```
Как видите, каждый запрос генерирует новые креды. Нигде на диске постоянный пароль не хранится.

### 4.3 VSO кладёт динамические креды в k8s Secret

Теперь создадим CRD Vault Secrets Operator, чтобы он взял на себя работу по извлечению этих кредов в k8s Secret.

```bash
cat << 'EOF' > manifests/vault/vso-secrets.yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultConnection
metadata:
  name: default
  namespace: lab
spec:
  address: http://vault.lab.svc.cluster.local:8200
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: default
  namespace: lab
spec:
  method: kubernetes
  mount: kubernetes
  kubernetes:
    role: vso-role
    serviceAccount: vso-auth
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultDynamicSecret
metadata:
  name: pg-dynamic-creds
  namespace: lab
spec:
  vaultAuthRef: default
  path: database/creds/dynrole      # Путь в Vault
  destination:
    name: pg-dynamic-creds          # Имя создаваемого k8s Secret
    create: true
EOF

kubectl -n lab apply -f manifests/vault/vso-secrets.yaml
```

Подождем пару секунд и проверим:
```bash
sleep 8
kubectl -n lab get secret pg-dynamic-creds -o jsonpath='{.data.username}' | base64 -d; echo
# v-kubernet-dynrole-XXXX   <- Vault-сгенерированный postgres-юзер, попал в Secret через VSO
```

> ✅ **Прогнано:** VSO залогинился в Vault, запросил динамический секрет и положил его в `Secret/pg-dynamic-creds`.
> Так как мы установили TTL роли в 1 минуту (1m), VSO будет автоматически перевыпускать секрет (ротировать) до истечения срока действия. Если вы посмотрите на этот же секрет через ~45-60 секунд, вы увидите, что username изменился — оператор прозрачно обновил k8s Secret! Приложение, монтирующее Secret как volume, может отследить inotify-эвенты на изменение файла и подгрузить новый пароль.

---

## Сравнение подходов

Какую систему использовать? Вот матрица выбора:

| Подход | Где живёт секрет | Git-safe? | Ротация | Идеальный Use-case |
|--------|------------------|-----------|---------|-------------------|
| **Обычный Secret** | etcd (base64) | ❌ нет | нет | Никогда не коммитить. Только для локальной разработки. |
| **Encryption-at-rest** | etcd (шифр) | — | нет | Базовая защита кластера. Включается админами (ops) всегда для prod. |
| **Sealed Secrets** | git (шифр) + Secret | ✅ да | вручную | Инди-проекты, GitOps-репозитории, где нет отдельного Vault/AWS. |
| **External Secrets (ESO)** | внешний менеджер (Vault/Cloud) | ✅ (ссылка) | авто (по refresh) | Enterprise с облачными провайдерами, синк из AWS SM / Azure Key Vault. |
| **Vault Dynamic (VSO)** | НЕ хранится (генерируется on-demand) | ✅ | авто (по TTL) | БД, облака. Максимальная безопасность (Zero Trust), короткоживущие креды. |

---

## Troubleshooting — частые проблемы и боевые инциденты

### Алгоритм диагностики проблем с секретами

Если ваше приложение "не видит" секрет или он не появляется, проверьте цепочку:
1. Есть ли целевой `Secret` в namespace? `kubectl get secret`
2. Если используется генератор (Sealed, ESO, VSO), посмотрите статус CRD ресурса: `kubectl describe externalsecret <name>` или `kubectl describe sealedsecret <name>`.
3. Посмотрите логи контроллера оператора.

### Инцидент 1: SealedSecret не расшифровывается (Secret не появляется)

**Симптом:** Вы применили `SealedSecret`, но `Secret` не был создан. При выполнении `kubectl describe sealedsecret app-creds` вы видите в Events: `Error updating secret: no key could decrypt secret`.
**Причина:** `SealedSecret` был зашифрован публичным ключом от **другого** кластера. (Например, вы скачали манифест из чужого туториала).
**Решение:** Секрет невозможно расшифровать. Вам необходимо заново сгенерировать его с помощью локального `kubeseal`, подключенного к текущему целевому кластеру: `kubeseal --fetch-cert`, чтобы пересоздать `encryptedData`.

### Инцидент 2: ExternalSecret висит в статусе SecretStoreNotFound или ProviderError

**Симптом:** `kubectl get externalsecret` показывает статус `SecretStoreNotFound` или `ProviderError`.
**Причина:** ESO не может найти указанный в `secretStoreRef` ресурс, либо (в случае `ProviderError`) не может подключиться к AWS/Vault. Возможно, неправильно настроены IAM Roles / ServiceAccounts, или сеть кластера не имеет доступа к облачному API.
**Решение:**
1. Проверьте статус самого SecretStore: `kubectl describe secretstore <name>`.
2. В логах ESO (`kubectl logs -n external-secrets deploy/external-secrets`) найдите детальную ошибку HTTP-вызова.

### Инцидент 3: VaultDynamicSecret не обновляет Secret (client error: error auth)

**Симптом:** `VaultDynamicSecret` не синхронизируется. В логах VSO или в Events: `client error: error auth: error calling tokenreview`.
**Причина:** VSO пытается аутентифицироваться в Vault через Kubernetes Auth. Vault обращается обратно в кластер (через `TokenReview` API), чтобы проверить валидность токена ServiceAccount'а. Если у `vso-auth` (или у Vault) нет ClusterRoleBinding на `system:auth-delegator`, проверка отклоняется.
**Решение:** Создать `ClusterRoleBinding` для прав `system:auth-delegator` (как мы сделали в Части 4.1).

---

## Проверка модуля

Запустите скрипт автопроверки, чтобы убедиться, что все задания и манифесты применены корректно:

```bash
bash verify/verify.sh
```

Этот скрипт проверит состояние контроллеров Sealed Secrets, ESO, VSO, а также убедится в работоспособности Vault и генерации динамических секретов.

---

## Финальная карта ресурсов модуля

| Ресурс / Компонент | Часть | Что демонстрирует |
|--------------------|-------|-------------------|
| `etcd-probe` (Secret) | 1 | Plaintext данные в etcd (отключенный encryption-at-rest) |
| `app-creds` (SealedSecret → Secret) | 2 | Криптографически безопасный для Git секрет |
| `fake-store` + `db-from-eso` (ESO) | 3 | Периодическую синхронизацию из внешнего менеджера |
| `vault` + `pg` + VSO CRs | 4 | Полную динамику кредов (Vault-generated short-lived users) |

---

## Контрольные вопросы

### Блок 1: Базовая безопасность и etcd
1. В чём заключаются фундаментальные отличия и риски использования обычных `Secret` в Kubernetes (даже с base64) по сравнению с включённым `encryption-at-rest` в etcd?
2. Какие провайдеры `EncryptionConfiguration` считаются самыми безопасными для production (kms vs aescbc)?

### Блок 2: GitOps и Sealed Secrets
3. Архитектура Sealed Secrets подразумевает асимметричное шифрование. Каким образом `kubeseal` понимает, каким публичным ключом шифровать данные, и как предотвращается расшифровка секрета на другом кластере?
4. Почему критически важно создавать резервные копии ключей Sealed Secrets контроллера?

### Блок 3: Внешние провайдеры (ESO)
5. В чем разница между `SecretStore` и `ExternalSecret` в ESO?
6. Что находится в Git-репозитории при использовании External Secrets Operator, а что во внешнем хранилище?

### Блок 4: Динамические секреты Vault
7. Объясните механизм аутентификации Vault Secrets Operator (VSO) в кластере Vault. Какую роль в этом играет Kubernetes ServiceAccount и права `system:auth-delegator`?
8. Динамические секреты Vault создают новые учетные данные on-demand с заданным TTL. Каким образом обеспечивается автоматическая ротация этих секретов в Kubernetes Secret без ручного вмешательства, и как приложение узнаёт об их обновлении?

---

## Практические задания (отработка)

> Выполняйте на живом кластере; проверяйте себя командами и `verify/verify.sh`.

1. Прочитайте Secret прямо из etcd (etcdctl по SSH) и убедитесь, что он plaintext (нет `k8s:enc:`).
2. Запечатайте свой тестовый Secret через `kubeseal`, примените SealedSecret, проверьте созданный Secret; попробуйте применить его на "другом кластере" (или в другом namespace) — убедитесь, что он не расшифровывается.
3. ESO: смените значение пароля в манифесте `SecretStore` (fake-store) и убедитесь, что синхронизированный Secret обновился автоматически благодаря `refreshInterval`.
4. Vault: дважды прочитайте `database/creds/dynrole` напрямую в Vault и покажите, что username генерируется КАЖДЫЙ раз новый.
5. VSO: удалите Secret `pg-dynamic-creds` руками и убедитесь, что Vault Secrets Operator его мгновенно восстановит ( reconciliation loop ).

---

## Чему вы научились

В этом модуле вы научились:
- Проверять и понимать шифрование секретов на уровне базы данных etcd (encryption-at-rest).
- Использовать Sealed Secrets для безопасного хранения конфиденциальной информации в Git (GitOps way).
- Интегрировать Kubernetes с внешними облачными хранилищами через External Secrets Operator (ESO).
- Развертывать Vault в development-режиме и настраивать динамические короткоживущие роли для баз данных.
- Подключать Vault Secrets Operator (VSO) для автоматической ротации кредов.
- Траблшутить типичные ошибки авторизации и шифрования в секрет-операторах.

---

## Уборка

Для очистки кластера от всех созданных в ходе лабы ресурсов, включая поды Vault, Postgres, CRD и webhook-и, запустите скрипт:

```bash
bash verify/cleanup.sh
```

---

## Шпаргалка

```bash
# Чтение секрета прямо из кластера в base64 декодированном виде
kubectl get secret <secret_name> -o jsonpath='{.data.password}' | base64 -d

# Создание SealedSecret
kubectl create secret generic my-secret --from-literal=key=val --dry-run=client -o yaml | \
  kubeseal --controller-namespace kube-system -o yaml > sealed.yaml

# Получение публичного сертификата Sealed Secrets
kubeseal --fetch-cert --controller-namespace kube-system > pub-cert.pem

# Ручное создание секрета с TLS сертификатом
kubectl create secret tls my-tls-secret --cert=path/to/cert.pem --key=path/to/key.pem

# Узнать статус внешнего секрета ESO
kubectl describe externalsecret <es_name>
```


## Решения (Solutions)
В данном модуле добавлены подробные решения для сломанных сценариев в папке `solutions/`. Пожалуйста, изучите их для лучшего понимания.
