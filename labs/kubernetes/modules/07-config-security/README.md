# Лабораторная работа 07: Конфигурация и безопасность (ConfigMap, Secret, RBAC, securityContext)

## Оглавление
<!-- TOC -->
- [Предварительные требования](#-)
- [Стартовая проверка](#-)
- [Часть 1: ConfigMap](#-1-configmap)
  - [Теория для изучения перед частью](#----)
  - [1.1 ConfigMap как env (envFrom)](#11-configmap--env-envfrom)
- [Часть 2: Secret](#-2-secret)
  - [Теория для изучения перед частью](#----)
  - [2.1 Secret как env](#21-secret--env)
  - [2.2 base64 ≠ безопасность](#22-base64--)
- [Часть 3: ServiceAccount и RBAC](#-3-serviceaccount--rbac)
  - [Теория для изучения перед частью](#----)
  - [3.1 SA + Role + RoleBinding](#31-sa--role--rolebinding)
  - [3.2 Полный список прав SA](#32----sa)
- [Часть 4: securityContext и ужесточение запуска](#-4-securitycontext---)
  - [Теория для изучения перед частью](#----)
  - [4.1 securityContext у config-demo](#41-securitycontext--config-demo)
- [Часть 5: Troubleshooting — боевые инциденты](#-5-troubleshooting---)
  - [Инцидент 1: под не стартует — `runAsNonRoot` против root-образа](#-1-----runasnonroot--root-)
  - [Инцидент 2: приложение получает `403 Forbidden` от API](#-2---403-forbidden--api)
  - [Инцидент 3: `readOnlyRootFilesystem` ломает приложение](#-3-readonlyrootfilesystem--)
- [Проверка модуля](#-)
- [Финальная карта ресурсов модуля](#---)
- [Теоретические вопросы (итоговые)](#--)
  - [Блок 1: ConfigMap / Secret](#-1-configmap--secret)
  - [Блок 2: RBAC](#-2-rbac)
  - [Блок 3: securityContext](#-3-securitycontext)
- [Практические задания (отработка)](#--)
- [Шпаргалка](#)
- [Чему вы научились](#--)
- [Уборка](#)
<!-- /TOC -->


> ⏱ время ~20 мин · сложность 2/5 · пререквизиты: модуль 03

Цель: научиться отделять конфигурацию от образа (`ConfigMap`/`Secret`),
выдавать подам минимальные права к API (`ServiceAccount` + RBAC) и ужесточать
запуск контейнеров (`securityContext`). К концу модуля вы понимаете, почему
base64 ≠ шифрование, как проверить права через `auth can-i` и почему
«хороший» security-context может уронить под.

---

## Предварительные требования

```bash
# kubeconfig нашего кластера (Kubespray); на другом стенде — свой путь/контекст
export KUBECONFIG=/root/.kube/kubespray.conf
kubectl create ns lab --dry-run=client -o yaml | kubectl apply -f -
kubectl -n lab delete deploy,sts,ds,job,cronjob,svc,pvc,pod,ingress,netpol,cm,secret,sa,role,rolebinding --all --ignore-not-found 2>/dev/null
```

---

## Стартовая проверка

```bash
# Дефолтный ServiceAccount есть в каждом namespace — от него по умолчанию
# работают все поды, если не указать другой.
kubectl -n lab get serviceaccount default
# NAME      SECRETS   AGE
# default   0         ...
```

---

## Часть 1: ConfigMap

### Теория для изучения перед частью

- **ConfigMap** хранит НЕсекретный конфиг (флаги, уровни логов, URL) отдельно от
  образа — один образ, разный конфиг под окружения.
- **Три способа инъекции:** отдельные env (`valueFrom.configMapKeyRef`), все
  ключи разом (`envFrom.configMapRef`), файлы (`volume` с `configMap`).

**env vs volume — что выбрать:**

| | env / envFrom | volume (файлы) |
|---|---|---|
| Обновление без рестарта пода | ✗ фиксируется на старте | ✓ файлы обновляются (~до минуты) |
| Что видит приложение | переменные окружения | файлы (нужно перечитать самому) |
| Удобно для | флаги, URL, мелкие значения | большие/целые файлы (`nginx.conf`, сертификаты) |
| Атомарность обновления | — | ✓ (k8s меняет через symlink-swap, нет «полу-обновления») |
| Риск утечки | env видны в дочерних процессах/`inspect` | чуть лучше изолированы |

- **Лимит и иммутабельность.** ConfigMap (и Secret) ≤ **1 MiB** (ограничение
  объекта в etcd) — большие файлы туда не класть. `immutable: true` запрещает
  правки (только пересоздать) и РАЗГРУЖАЕТ kube-apiserver: kubelet перестаёт
  следить за изменениями (полезно при тысячах подов).

#### Механика обновления тома: atomic symlink-swap

Как ConfigMap-том обновляется без рестарта пода и почему это **атомарно**.
kubelet монтирует не файлы напрямую, а двухуровневую конструкцию из симлинков:

```
/etc/cfg/
  app.conf  ──симлинк──►  ..data/app.conf
  ..data    ──симлинк──►  ..2026_06_04_23_06_13.3254397790/   (timestamped каталог)
                              └── app.conf   (реальный файл, версия v1)

ОБНОВЛЕНИЕ: kubelet создаёт НОВЫЙ каталог ..2026_06_04_23_08_40.../ со всеми
файлами новой версии, затем ОДНОЙ операцией rename переставляет симлинк
..data на него. Приложение никогда не видит «полу-записанный» набор файлов —
переключение всех ключей разом.
```

**Reality (проверено на кластере):**
```bash
kubectl -n lab exec <pod> -- ls -la /etc/cfg
#   ..data -> ..2026_06_04_23_06_13.3254397790
#   app.conf -> ..data/app.conf
# После kubectl apply нового ConfigMap (~14с спустя):
#   ..data -> ..2026_06_04_23_08_40.2357228212   <- симлинк переставлен на новый каталог
#   app.conf уже отдаёт новое значение
```

- **Задержка 30–90с (у нас вышло ~14с).** Том обновляется НЕ мгновенно: kubelet
  синхронизирует тома периодически (`syncFrequency`, по умолч. ~1 мин) плюс TTL
  кэша watch. Поэтому «поправил ConfigMap» и «приложение увидело» разнесены во
  времени — это не баг.
- **Приложение должно ПЕРЕЧИТАТЬ файл само.** k8s обновит файл на диске, но не
  пошлёт сигнал процессу. Либо приложение следит за файлом (inotify/таймер), либо
  нужен `rollout restart` / reloader-сайдкар.
- **⚠️ subPath ломает обновление.** `volumeMounts.subPath` монтирует ОДИН файл по
  inode напрямую, мимо `..data`-симлинка — такой файл **не обновляется** при правке
  ConfigMap (только при пересоздании пода). Классическая ловушка.
- env/envFrom не обновляются вовсе (фиксируются на старте) — см. таблицу выше.

---

**Цель:** прокинуть конфиг в приложение без пересборки образа.

**Ресурсы:** `manifests/config/cm.yaml` (`app-config-lab`) + `deploy.yaml`
(`config-demo`).

---

### 1.1 ConfigMap как env (envFrom)

```bash
kubectl -n lab apply -f manifests/config/cm.yaml
kubectl -n lab apply -f manifests/config/deploy.yaml
kubectl -n lab rollout status deploy/config-demo --timeout=120s

# Все ключи ConfigMap попали в окружение контейнера (envFrom)
kubectl -n lab exec deploy/config-demo -- env | grep -E "APP_MODE|FEATURE_FLAG|LOG_LEVEL"
# APP_MODE=lab
# FEATURE_FLAG=true
# LOG_LEVEL=info
```

> Поменяйте значение в ConfigMap и `kubectl apply` — в поде env НЕ изменится,
> пока под не пересоздан (`kubectl rollout restart deploy/config-demo`). Это
> типичная ловушка «поправил ConfigMap, а приложение не видит».

**Контрольные вопросы:**
1. Три способа прокинуть ConfigMap в контейнер — чем отличаются?
2. Почему правка ConfigMap не долетает до env работающего пода?
3. Когда конфиг как volume предпочтительнее, чем как env?

---

## Часть 2: Secret

### Теория для изучения перед частью

- **Secret** — для чувствительных данных (пароли, токены, ключи, TLS). Типы:
  `Opaque` (произвольные), `kubernetes.io/dockerconfigjson` (pull-доступ),
  `kubernetes.io/tls`.
- ⚠️ **base64 — это НЕ шифрование.** В etcd Secret лежит в base64 (кодирование,
  не защита). Любой с доступом `get secret` или к etcd прочитает его.
- **Реальная защита:** RBAC на `secrets`, encryption-at-rest в etcd
  (EncryptionConfiguration), внешние менеджеры (Vault, Cloud Secret Manager),
  не коммитить Secret в git.

- **`data` vs `stringData` при создании.** `data` — значения уже в base64 (кодируешь
  сам). `stringData` — значения ПЛЕЙН-текстом, apiserver сам закодирует при
  сохранении (удобно писать руками); поле write-only — в `get -o yaml` вернётся
  уже как `data` (base64).

- **Почему Secret-as-env рискованнее Secret-as-volume.** Значение в env:
  наследуется ДОЧЕРНИМИ процессами; видно в `/proc/<pid>/environ`; всплывает в
  `crictl/docker inspect` и часто в крэш-дампах/логах приложения. Том с Secret
  изолирован лучше (только файл, права 0400, можно `defaultMode`). Для самого
  чувствительного — монтировать томом, не пихать в env.

---

**Цель:** прокинуть секрет в приложение и понять, что base64 ничего не скрывает.

**Ресурсы:** `manifests/secrets/secret.yaml` (`app-secret-lab`) + `deploy.yaml`.

---

### 2.1 Secret как env

```bash
kubectl -n lab apply -f manifests/secrets/secret.yaml
kubectl -n lab apply -f manifests/secrets/deploy.yaml
kubectl -n lab rollout status deploy/secret-demo --timeout=120s

kubectl -n lab exec deploy/secret-demo -- env | grep DEMO_
# DEMO_USERNAME=demo-user
# DEMO_PASSWORD=demo-password
```

### 2.2 base64 ≠ безопасность

```bash
# Secret в API лежит в base64 — это легко обратимо, НЕ шифрование:
kubectl -n lab get secret app-secret-lab -o jsonpath='{.data.PASSWORD}'; echo
# ZGVtby1wYXNzd29yZA==
kubectl -n lab get secret app-secret-lab -o jsonpath='{.data.PASSWORD}' | base64 -d; echo
# demo-password        <- расшифровывается одной командой
```

> Вывод: Secret защищает не «кодированием», а **доступом** (RBAC) и шифрованием
> etcd. Относитесь к `get secret` как к доступу к самим паролям.

**Контрольные вопросы:**
1. Почему base64 в Secret не считается защитой?
2. Чем `Secret` реально отличается от `ConfigMap` по обращению с ним?
3. Какие три механизма реально защищают секреты в кластере?

---

## Часть 3: ServiceAccount и RBAC

### Теория для изучения перед частью

- **ServiceAccount (SA)** — «личность» пода в API. Каждый под работает от SA (по
  умолчанию `default`) и получает его токен, которым обращается к API.
- **RBAC:** `Role` (права в одном namespace) / `ClusterRole` (кластерные);
  `RoleBinding` / `ClusterRoleBinding` связывают права с субъектом (SA,
  пользователь, группа). Право = `apiGroups` × `resources` × `verbs`.
- **Least privilege:** выдавать минимум — конкретные verbs на конкретные ресурсы
  в конкретном namespace. `*` на всё — антипаттерн.

**Цепочка авторизации пода (кто на что имеет право):**

```
Pod (spec.serviceAccountName: pod-reader)
   │  работает от
   ▼
ServiceAccount/pod-reader ──(subject)──> RoleBinding ──(roleRef)──> Role
                                                                      │
            ЗАПРОС к API проверяется: subject есть в binding? ◄───────┤
            роль разрешает verb на resource в apiGroup?               │
                                                                      ▼
                                   rules: apiGroups[""] × resources["pods"] × verbs[get,list,watch]
```

**Дефолтные ClusterRole (агрегированные, есть в любом кластере) — не изобретать своё:**

| ClusterRole | Что даёт | Кому |
|-------------|----------|------|
| `view` | read-only почти всё в ns, **КРОМЕ secrets** | аудиторы, read-дашборды |
| `edit` | read/write workloads (deploy/svc/cm/secret), **НЕ** RBAC/quota | разработчики |
| `admin` | `edit` + управление Role/RoleBinding/quota В ns | владелец namespace |
| `cluster-admin` | **ВСЁ** в кластере (god-mode) | только админы кластера |

> Привязал `view`/`edit`/`admin` к SA через RoleBinding — и не пишешь правила
> руками. `cluster-admin` через ClusterRoleBinding — крайне осторожно.

#### Как под получает токен: projected-том и автоматическая ротация

С k8s 1.22 под получает токен SA не из вечного Secret, а через **projected-том**
с тремя источниками (kubelet собирает их в `/var/run/secrets/kubernetes.io/serviceaccount/`):

```
volume kube-api-access-xxxxx (projected):
  ├─ serviceAccountToken: {expirationSeconds: 3607, path: token}  ← короткоживущий JWT
  ├─ configMap: kube-root-ca.crt          (path: ca.crt — доверять API-серверу)
  └─ downwardAPI: metadata.namespace      (path: namespace)
```

**Reality (проверено на coredns-поде):** источник `serviceAccountToken` с
`expirationSeconds: 3607` (~1 час). Это **BoundServiceAccountToken**:

- **Короткий срок + авто-ротация.** kubelet запрашивает токен через TokenRequest
  API и **перевыпускает** его, не дожидаясь истечения (примерно на 80% срока или
  раз в ~1ч). Приложение должно ПЕРЕЧИТЫВАТЬ файл токена, а не кэшировать его
  навсегда (старые клиенты, читавшие токен один раз на старте, ломаются).
- **Audience-bound и bound-to-object.** JWT содержит `aud` (для кого токен валиден),
  `exp`/`iat` (срок), и claim `kubernetes.io` с привязкой к конкретному **Pod**
  (и его UID). Удалили под — токен инвалидируется на сервере, его нельзя
  переиспользовать. Это главный плюс над старыми вечными Secret-токенами.
- **Отключение.** `automountServiceAccountToken: false` (на SA или в Pod) убирает
  том вовсе — для подов, которым API не нужен (снижение поверхности атаки).
- Связь: токен — это «личность» для цепочки RBAC выше (AuthN-этап перед AuthZ,
  см. путь запроса в модуле 01).

---

**Цель:** дать SA права ТОЛЬКО на чтение подов и проверить их.

**Ресурсы:** `manifests/rbac/{sa,role,rolebinding}.yaml` (`pod-reader`).

---

### 3.1 SA + Role + RoleBinding

```bash
kubectl -n lab apply -f manifests/rbac/sa.yaml
kubectl -n lab apply -f manifests/rbac/role.yaml
kubectl -n lab apply -f manifests/rbac/rolebinding.yaml

# Role даёт только get/list/watch на pods — проверим это через can-i:
kubectl -n lab auth can-i get pods    --as=system:serviceaccount:lab:pod-reader
# yes
kubectl -n lab auth can-i delete pods --as=system:serviceaccount:lab:pod-reader
# no       <- delete не входит в Role => запрещён (least privilege)
kubectl -n lab auth can-i get secrets --as=system:serviceaccount:lab:pod-reader
# no       <- secrets не упомянуты => запрещены
```

> `--as=system:serviceaccount:<ns>:<name>` — имперсонация SA. `auth can-i` —
> лучший способ проверить RBAC, не разворачивая поды.

### 3.2 Полный список прав SA

```bash
kubectl -n lab auth can-i --list --as=system:serviceaccount:lab:pod-reader | grep -iE "pods|secrets"
# pods    [get list watch]
# (secrets в списке нет => нет прав)
```

**Контрольные вопросы:**
1. Что такое ServiceAccount и как он связан с доступом пода к API?
2. Разница `Role`/`ClusterRole` и `RoleBinding`/`ClusterRoleBinding`?
3. Чем опасен `verbs: ["*"]` на `resources: ["*"]`?
4. Как проверить право SA, не создавая под?

---

## Часть 4: securityContext и ужесточение запуска

### Теория для изучения перед частью

- **securityContext** ограничивает контейнер: `runAsNonRoot: true` (запрет root),
  `runAsUser: N` (конкретный UID), `allowPrivilegeEscalation: false` (запрет
  setuid-эскалации), `readOnlyRootFilesystem: true` (только чтение корня),
  `capabilities` (drop ALL), `seccompProfile`.
- **Pod Security Standards:** `privileged` (без ограничений), `baseline`
  (разумный минимум), `restricted` (жёстко: non-root, drop caps, RO fs). Включаются
  лейблами на namespace (`pod-security.kubernetes.io/enforce`). Полевое сравнение
  профилей и принудительный enforce — в модуле 14 (PSA + ValidatingAdmissionPolicy).

**Паттерн capabilities «drop ALL + добавить минимум»** (требование `restricted`):

```yaml
securityContext:
  allowPrivilegeEscalation: false
  runAsNonRoot: true
  capabilities:
    drop: ["ALL"]                  # снять ВСЕ линукс-capability (даже у root в контейнере)
    add:  ["NET_BIND_SERVICE"]     # вернуть ТОЛЬКО нужное (напр. bind на порт <1024)
  seccompProfile: { type: RuntimeDefault }
```

> Linux capabilities дробят всемогущество root на ~40 флагов (`NET_ADMIN`,
> `SYS_TIME`, …). Контейнеру почти всегда нужно 0-1 из них — поэтому безопасный
> дефолт: снять ВСЕ, потом добавить точечно. `drop:[ALL]` сильнее, чем
> `runAsNonRoot`: ограничивает даже процессы, что всё же стартовали от root.

---

**Цель:** увидеть включённый security-context и его требования.

---

### 4.1 securityContext у config-demo

```bash
# config-demo собран на nginx-unprivileged (не-root) + runAsNonRoot — стартует ОК
kubectl -n lab get deploy config-demo \
  -o jsonpath='{.spec.template.spec.containers[0].securityContext}{"\n"}'
# {"allowPrivilegeEscalation":false,"runAsNonRoot":true}

# От какого UID реально работает процесс:
kubectl -n lab exec deploy/config-demo -- id
# uid=101(nginx) gid=101(nginx)     <- не root (0), политика соблюдена
```

> Ключевое: `runAsNonRoot: true` сам по себе не делает образ не-root — он лишь
> ЗАПРЕЩАЕТ root. Если образ стартует от root, под не поднимется (см. Часть 5).
> Образ должен быть собран под не-root UID (как `nginx-unprivileged`).

**Контрольные вопросы:**
1. Что делает `runAsNonRoot: true` и чего он НЕ делает?
2. Зачем `readOnlyRootFilesystem` и какие приложения он сломает?
3. Что такое Pod Security Standards и чем `restricted` строже `baseline`?

---

## Часть 5: Troubleshooting — боевые инциденты

### Инцидент 1: под не стартует — `runAsNonRoot` против root-образа

Оформлен в `broken/scenario-01/`. Здесь — полный цикл.

**Воспроизведение:**

```bash
# Образ nginx (стартует от root) + securityContext runAsNonRoot:true — конфликт
kubectl -n lab apply -f broken/scenario-01/deploy.yaml
sleep 6
```

**Диагностика:**

```bash
kubectl -n lab get pods -l app=security-fail
# security-fail-...   0/1   CreateContainerConfigError   0   6s

kubectl -n lab describe pod -l app=security-fail | grep -A2 "Error:"
# Error: container has runAsNonRoot and image will run as root
#        (pod: "security-fail-...", container: app)
```

**Решение:**

```bash
# Использовать не-root образ (или задать runAsUser: 101)
kubectl -n lab apply -f solutions/01-run-as-nonroot-fail/deploy.yaml
kubectl -n lab rollout status deploy/security-fail --timeout=120s
kubectl -n lab exec deploy/security-fail -- id   # uid != 0
```

**Профилактика:** запускать non-root образы (`*-unprivileged`, distroless) или
явно задавать `runAsUser`; включать `runAsNonRoot` в стандарт и тестировать в CI.

### Инцидент 2: приложение получает `403 Forbidden` от API

```bash
# Под под SA pod-reader пытается УДАЛИТЬ под -> RBAC запрещает (Role только read):
kubectl -n lab auth can-i delete pods --as=system:serviceaccount:lab:pod-reader
# no
# В реальном приложении это выглядит как: Error from server (Forbidden):
#   pods is forbidden: User "system:serviceaccount:lab:pod-reader" cannot delete
#   resource "pods" ... Лечение: добавить нужный verb в Role ОСОЗНАННО (least privilege).
```

### Инцидент 3: `readOnlyRootFilesystem` ломает приложение

```bash
# Многие образы пишут во временные каталоги (/tmp, /var/run). С RO-корнем они
# падают на запись. Лечение — НЕ открывать весь корень, а смонтировать emptyDir
# на нужные пути:
#   securityContext: { readOnlyRootFilesystem: true }
#   volumeMounts: [{ name: tmp, mountPath: /tmp }]
#   volumes: [{ name: tmp, emptyDir: {} }]
```

**Контрольные вопросы:**
1. Чем `CreateContainerConfigError` отличается от `CrashLoopBackOff` по причине?
2. Как выглядит RBAC-отказ на стороне приложения и как его чинить правильно?
3. Почему `readOnlyRootFilesystem` часто требует доп. `emptyDir`-томов?

---

## Проверка модуля

```bash
kubectl -n lab apply -f manifests/rbac/sa.yaml -f manifests/rbac/role.yaml -f manifests/rbac/rolebinding.yaml

bash verify/verify.sh
# [OK] module 07 verified
```

`verify.sh` проверяет: namespace `lab` → существует `ServiceAccount/pod-reader` →
`can-i get pods` = `yes` → `can-i delete pods` = `no`. Промежуточные проверки
молчат; при успехе печатается одна строка `[OK] module 07 verified`. Если RBAC
настроен неверно — `[FAIL] serviceaccount pod-reader cannot get pods` или
`... should not delete pods`.

---

## Финальная карта ресурсов модуля

| Ресурс | Тип | Что демонстрирует |
|--------|-----|-------------------|
| `app-config-lab` + `config-demo` | ConfigMap + Deployment | конфиг через envFrom, не-root образ |
| `app-secret-lab` + `secret-demo` | Secret + Deployment | секрет через env, base64 ≠ шифрование |
| `pod-reader` | SA + Role + RoleBinding | least-privilege RBAC (только чтение подов) |
| `security-fail` | Deployment (broken→fix) | runAsNonRoot против root-образа |

---

## Теоретические вопросы (итоговые)

### Блок 1: ConfigMap / Secret
1. Когда `ConfigMap`, когда `Secret`? Что делает их «секретность» реальной?
2. Почему правка ConfigMap-as-env не видна работающему поду?
3. Покажите одной командой, что base64 в Secret обратим.

### Блок 2: RBAC
4. Опишите цепочку Pod → SA → RoleBinding → Role (где проверяется право?).
5. Как `auth can-i --as=...` помогает аудировать права?
6. Чем опасен `*` в RBAC и как выглядит least privilege?
7. Назовите дефолтные ClusterRole view/edit/admin — что даёт каждый и почему
   `view` НЕ включает secrets?

### Блок 3: securityContext
7. Что гарантирует и чего НЕ гарантирует `runAsNonRoot: true`?
8. Назовите 4 поля securityContext для «restricted»-профиля.
9. Почему root-образ + `runAsNonRoot` даёт `CreateContainerConfigError`?

---

## Практические задания (отработка)

> Делайте на живом кластере; проверяйте себя командами и `verify/verify.sh`.

1. Прокиньте ConfigMap как env И как volume; поменяйте значение — покажите, что env не обновился без рестарта, а файл обновился.
2. Одной командой докажите обратимость base64 в Secret; смонтируйте Secret томом (mode 0400) вместо env.
3. Создайте SA+Role+RoleBinding только на чтение подов и проверьте права через `auth can-i --as=...`.
4. Привяжите к SA дефолтный ClusterRole `view` и убедитесь, что он НЕ даёт `get secrets`.
5. Воспроизведите `CreateContainerConfigError` (root-образ + `runAsNonRoot`) и почините не-root образом / `runAsUser`.

---

## Шпаргалка

```bash
# === ConfigMap / Secret ===
kubectl -n lab create cm myconf --from-literal=KEY=val --dry-run=client -o yaml
kubectl -n lab exec deploy/config-demo -- env | grep APP_
kubectl -n lab get secret app-secret-lab -o jsonpath='{.data.PASSWORD}' | base64 -d   # decode
kubectl -n lab rollout restart deploy/config-demo                                     # подхватить новый ConfigMap

# === RBAC ===
kubectl -n lab auth can-i get pods --as=system:serviceaccount:lab:pod-reader
kubectl -n lab auth can-i --list --as=system:serviceaccount:lab:pod-reader
kubectl -n lab describe rolebinding pod-reader

# === securityContext ===
kubectl -n lab get pod <p> -o jsonpath='{.spec.containers[0].securityContext}'
kubectl -n lab exec deploy/config-demo -- id                                          # под каким UID
kubectl -n lab describe pod <p> | grep -A2 "Error:"                                   # причина CreateContainerConfigError

# === Уборка ===
kubectl -n lab delete -k manifests/
```

---


## Чему вы научились

В этом модуле вы научились:
- Передаче конфигураций через ConfigMap и секретов через Secret
- Настройке ServiceAccount и политик доступа RBAC
- Ограничению прав процессов через SecurityContext

## Уборка

```bash
kubectl -n lab delete -k manifests/
# (ConfigMap, Secret, оба Deployment, SA/Role/RoleBinding)
```
