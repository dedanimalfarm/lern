# Лабораторная работа 07: Конфигурация и безопасность (ConfigMap, Secret, RBAC, securityContext)

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
kubectl -n lab delete deploy,sts,ds,job,cronjob,svc,pvc,pod,ingress,netpol,cm,secret,sa,role,rolebinding --all --ignore-not-found 2>/dev/null
kubectl create ns lab --dry-run=client -o yaml | kubectl apply -f -
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
- **Обновление:** значения, проброшенные как **env**, фиксируются на старте
  контейнера — изменение ConfigMap НЕ долетит без рестарта пода. Через **volume**
  файлы обновляются в работающем поде (с задержкой), но приложение должно само
  перечитать.

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
  лейблами на namespace (`pod-security.kubernetes.io/enforce`).

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
4. Опишите цепочку SA → (Cluster)Role → (Cluster)RoleBinding.
5. Как `auth can-i --as=...` помогает аудировать права?
6. Чем опасен `*` в RBAC и как выглядит least privilege?

### Блок 3: securityContext
7. Что гарантирует и чего НЕ гарантирует `runAsNonRoot: true`?
8. Назовите 4 поля securityContext для «restricted»-профиля.
9. Почему root-образ + `runAsNonRoot` даёт `CreateContainerConfigError`?

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

## Уборка

```bash
kubectl -n lab delete -k manifests/
# (ConfigMap, Secret, оба Deployment, SA/Role/RoleBinding)
```
