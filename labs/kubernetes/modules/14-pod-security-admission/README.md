# Лабораторная работа 14: Pod Security и Admission Control (PSA + ValidatingAdmissionPolicy)

## Оглавление
<!-- TOC -->
- [Предварительные требования](#предварительные-требования)
- [Стартовая проверка](#стартовая-проверка)
- [Часть 1: Pod Security Admission (PSA)](#часть-1-pod-security-admission-psa)
  - [1.1 Теория: Зачем нам изолировать поды? Введение в Linux-изоляцию](#11-теория-зачем-нам-изолировать-поды-введение-в-linux-изоляцию)
  - [1.2 Pod Security Standards (PSS) и их уровни](#12-pod-security-standards-pss-и-их-уровни)
  - [1.3 PSA vs PSP — почему PSP убрали и что взамен](#13-psa-vs-psp--почему-psp-убрали-и-что-взамен)
  - [1.4 Анатомия профиля restricted: детальный разбор полей](#14-анатомия-профиля-restricted-детальный-разбор-полей)
  - [1.5 Практика: restricted - good проходит, bad отклоняется](#15-практика-restricted---good-проходит-bad-отклоняется)
  - [1.6 Стратегия безопасной миграции: warn и audit на проде](#16-стратегия-безопасной-миграции-warn-и-audit-на-проде)
  - [1.7 Управление версионированием политик (enforce-version)](#17-управление-версионированием-политик-enforce-version)
- [Часть 2: ValidatingAdmissionPolicy (CEL)](#часть-2-validatingadmissionpolicy-cel)
  - [2.1 Теория: Эволюция кастомных политик и введение в VAP](#21-теория-эволюция-кастомных-политик-и-введение-в-vap)
  - [2.2 Основы языка CEL (Common Expression Language) для Kubernetes](#22-основы-языка-cel-common-expression-language-для-kubernetes)
  - [2.3 Архитектура VAP: Policy и Binding](#23-архитектура-vap-policy-и-binding)
  - [2.4 Практика: Запрет использования тега :latest](#24-практика-запрет-использования-тега-latest)
  - [2.5 Практика: Валидация обязательных меток (labels) и аннотаций](#25-практика-валидация-обязательных-меток-labels-и-аннотаций)
  - [2.6 Практика: Продвинутая логика — ограничение hostPort](#26-практика-продвинутая-логика--ограничение-hostport)
- [Часть 3: Policy engines (Kyverno / OPA Gatekeeper) — обзор и глубокое погружение](#часть-3-policy-engines-kyverno--opa-gatekeeper--обзор-и-глубокое-погружение)
  - [3.1 Когда VAP недостаточно? (Сценарии Mutation и Generation)](#31-когда-vap-недостаточно-сценарии-mutation-и-generation)
  - [3.2 Архитектура OPA Gatekeeper (Rego)](#32-архитектура-opa-gatekeeper-rego)
  - [3.3 Архитектура Kyverno (YAML-native)](#33-архитектура-kyverno-yaml-native)
  - [3.4 Сравнительная таблица и рекомендации по выбору](#34-сравнительная-таблица-и-рекомендации-по-выбору)
- [Часть 4: Troubleshooting (Углубленный дебаггинг)](#часть-4-troubleshooting-углубленный-дебаггинг)
  - [4.1 Теория: Строгий порядок конвейера Admission Control](#41-теория-строгий-порядок-конвейера-admission-control)
  - [4.2 Как читать отказы: определяем виновника по тексту](#42-как-читать-отказы-определяем-виновника-по-тексту)
  - [4.3 Инцидент 1: Под отклонён PSA (restricted) — пошаговое исправление](#43-инцидент-1-под-отклонен-psa-restricted--пошаговое-исправление)
  - [4.4 Инцидент 2: Легитимный под не создаётся из-за VAP (Ложноположительное срабатывание)](#44-инцидент-2-легитимный-под-не-создается-из-за-vap-ложноположительное-срабатывание)
  - [4.5 Инцидент 3: Опасные поды проникают в кластер (PSA «не срабатывает»)](#45-инцидент-3-опасные-поды-проникают-в-кластер-psa-не-срабатывает)
  - [4.6 Инцидент 4: Конфликт Mutating Webhook Service Mesh и PSA](#46-инцидент-4-конфликт-mutating-webhook-service-mesh-и-psa)
  - [4.7 Инцидент 5: Ошибки синтаксиса CEL и дебаг выражений](#47-инцидент-5-ошибки-синтаксиса-cel-и-дебаг-выражений)
- [Проверка модуля](#проверка-модуля)
- [Финальная карта ресурсов модуля](#финальная-карта-ресурсов-модуля)
- [Теоретические вопросы (итоговые)](#теоретические-вопросы-итоговые)
- [Практические задания (отработка)](#практические-задания-отработка)
- [Шпаргалка](#шпаргалка)
- [Чему вы научились](#чему-вы-научились)
- [Уборка](#уборка)
<!-- /TOC -->

> ⏱ время ~60 мин · сложность 4/5 · пререквизиты: Трек 1 (Основы k8s) и Трек 3 (Безопасность RBAC)

Цель: научиться применять концепцию эшелонированной защиты (Defense in Depth) в Kubernetes. Вы научитесь запрещать небезопасные и неконсистентные объекты **на входе** (admission), пока они не попали в `etcd` и кластер. В модуле глубоко разбирается встроенный механизм Pod Security Admission (PSA) для стандартов безопасности, а также новейший встроенный язык ValidatingAdmissionPolicy (VAP на CEL) для кастомной бизнес-логики без необходимости поддерживать тяжелые внешние вебхуки.

> 💡 **Важно**: Всё в этом модуле (за исключением обзора Kyverno/OPA) — **встроено в ядро Kubernetes**. PSA доступен как GA с версии 1.25, а VAP стал GA в версии 1.30. Это "коробочные" инструменты, которые вы обязаны знать.

---

## Предварительные требования

Для выполнения лабораторной работы вам понадобится доступ к Kubernetes кластеру (версии не ниже 1.30 для поддержки VAP в статусе GA).

```bash
# Убедитесь, что вы настроили контекст. 
# В нашем учебном стенде Kubespray это:
export KUBECONFIG=/root/.kube/kubespray.conf

# Подготовим неймспейсы для работы
kubectl get ns lab >/dev/null 2>&1 || kubectl create ns lab
kubectl delete ns lab-restricted --ignore-not-found 2>/dev/null

# Проверяем версию (должна быть >= 1.30 для VAP)
kubectl version -o json 2>/dev/null | grep -i gitVersion | head -1
```

## Стартовая проверка

Убедитесь, что ваш кластер находится в здоровом состоянии, так как admission контроллеры чувствительны к доступности kube-apiserver:
```bash
kubectl get nodes
kubectl get cs || true # componentstatuses может быть deprecated, но полезен для проверки
```

---

## Часть 1: Pod Security Admission (PSA)

### 1.1 Теория: Зачем нам изолировать поды? Введение в Linux-изоляцию

С точки зрения ядра Linux, **контейнер — это просто процесс**, обернутый в изоляционные механизмы (Namespaces) и ограничители ресурсов (Cgroups). В отличие от виртуальных машин, где у каждой ВМ есть свой собственный эмулируемый гипервизором виртуальный процессор и свое ядро ОС, **все контейнеры на ноде делят одно общее ядро Linux** с хостовой ОС (worker node).

Если процесс внутри контейнера запущен от имени пользователя `root` (UID 0), и механизмы изоляции настроены слабо, этот `root` имеет те же права внутри ядра Linux, что и `root` на самой ноде. В случае уязвимости в приложении (например, Remote Code Execution), злоумышленник получает шелл внутри контейнера с правами `root`. 

Имея root и излишние привилегии (capabilities), злоумышленник может осуществить **Escape to Host** (побег из контейнера). Например:
1. Выполнить `mount`, чтобы примонтировать файловую систему ноды `/` к себе.
2. Прочитать `/var/lib/kubelet/kubeconfig` и получить админские права на кластер.
3. Прочитать `/etc/shadow` хоста.
4. Внедрить вредоносный модуль ядра (kernel module), который останется даже после удаления пода.
5. Использовать `hostNetwork` для перехвата сетевого трафика соседних контейнеров через `tcpdump`.

Для предотвращения этого в Kubernetes есть механизмы безопасности, ограничивающие контейнеры.

### 1.2 Pod Security Standards (PSS) и их уровни

Для стандартизации подходов к безопасности подов Kubernetes Sig-Auth разработал **Pod Security Standards (PSS)**. Это три официальных стандарта (или профиля) безопасности:

- **`privileged` (Привилегированный)**: Полностью открытый профиль. Ограничения отсутствуют. Разрешает эскалацию привилегий, доступ к сети хоста и любые тома. 
  *Где применяется*: Системные компоненты управления нодой (CNI плагины, kube-proxy, агенты мониторинга вроде Node Exporter), которым нужен полный доступ к ядру и оборудованию.
  
- **`baseline` (Базовый)**: "Золотая середина". Запрещает очевидно опасные вещи (например, `hostNetwork`, монтирование `hostPath`, `privileged: true`), но не накладывает жестких ограничений, которые требуют изменения кода приложения. В baseline можно запускать контейнеры от `root`.
  *Где применяется*: Переходный этап, либо дефолтный профиль для большинства стандартных корпоративных приложений, которые исторически собирались под root и не могут быть быстро переписаны.

- **`restricted` (Ограниченный)**: Максимально строгий профиль, следующий лучшим практикам безопасности (Best Practices). 
  *Где применяется*: Критичные финансовые приложения, multi-tenant кластеры. Требует существенной доработки манифестов и Dockerfile'ов (контейнер должен уметь работать от непривилегированного пользователя).

Механизм, который **применяет** эти стандарты в кластере, называется **Pod Security Admission (PSA)**.

### 1.3 PSA vs PSP — почему PSP убрали и что взамен

Если вы работали с кластерами версий 1.15-1.20, вы помните **PodSecurityPolicy (PSP)**. PSP был отдельным API-ресурсом (CRD-подобным), который делал то же самое. Однако PSP был **официально удален в версии 1.25**.

| Характеристика | PodSecurityPolicy (PSP) - Удален | Pod Security Admission (PSA) - Актуален |
|---|---|---|
| Архитектура | Отдельные объекты `PodSecurityPolicy` | Встроенные фиксированные профили в коде k8s |
| Привязка | Через `RoleBinding`. Политика применялась к `ServiceAccount` пода или пользователю. | Простая метка (label) на уровне `Namespace`. |
| Проблема дебага | Если подпадало несколько PSP, выбиралась первая по алфавиту. Было абсолютно непредсказуемо. | Детерминированно: работает тот профиль, метка которого стоит на Namespace. |
| Мутация подов | PSP мог МУТИРОВАТЬ под (автоматически подставлять `runAsUser`). | PSA **ТОЛЬКО ВАЛИДИРУЕТ**. Он ничего не меняет, только отвечает "Да" или "Нет". |
| Гибкость | Можно было писать свои "сборные солянки" правил. | Фиксированные 3 профиля. Кастомная логика вынесена в VAP (Часть 2). |

**Почему PSP убили?**
Потому что его внедрение на существующем кластере было минным полем. Мутирующее поведение приводило к тому, что разработчик деплоил один манифест, а в кластере оказывалось совершенно другое. Зависимость от RBAC делала аудит политик невозможным для человека без скриптов. PSA решает эту проблему гениально просто: "Один Namespace — Один профиль".

### 1.4 Анатомия профиля restricted: детальный разбор полей

Чтобы под прошел проверку PSA с профилем `restricted`, его `securityContext` должен строго соответствовать набору требований. Рассмотрим их, ответив на вопрос "почему это важно?":

1. **`runAsNonRoot: true`**
   - **Зачем:** Запрещает запуск процессов с UID 0. Если хакер пробьет приложение, у него будет оболочка непривилегированного пользователя, который не может читать критичные файлы даже внутри контейнера.
   - **В манифесте:** Требуется как на уровне Pod `securityContext`, так и на уровне контейнеров.
   
2. **`allowPrivilegeEscalation: false`**
   - **Зачем:** Блокирует использование suid/sgid бинарников (например, команд `sudo` или `su` внутри контейнера). Если процесс запущен как `uid 1000`, он никогда не сможет повысить свои права до root, даже если найдет suid-бинарник.
   
3. **`capabilities: drop: ["ALL"]`**
   - **Зачем:** Ядро Linux делит root-права на десятки "Capabilities" (например, `CAP_NET_ADMIN` позволяет управлять сетью, `CAP_CHOWN` менять владельца файла). По умолчанию Docker/Kubernetes оставляет контейнеру около 14 capabilities. Профиль restricted требует явно сбросить их все.
   - **Исключения:** Разрешено добавлять только `NET_BIND_SERVICE` (если приложению нужно слушать порты < 1024).

4. **`seccompProfile: type: RuntimeDefault`**
   - **Зачем:** Seccomp (Secure Computing mode) фильтрует системные вызовы (syscalls), которые процесс может отправлять к ядру Linux. Дефолтный профиль рантайма (containerd/docker) блокирует около 40 из 300+ сисколлов ядра (такие как `kexec_load`, `bpf` и другие опасные вызовы). В restricted этот профиль обязателен.

### 1.5 Практика: restricted - good проходит, bad отклоняется

Давайте создадим неймспейс и применим к нему профиль `restricted` в режиме `enforce` (жесткая блокировка).

```bash
mkdir -p manifests broken/scenario-01

# 1. Манифест Namespace с меткой PSA
cat <<EOF > manifests/restricted-ns.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: lab-restricted
  labels:
    # Главная метка, включающая блокировку
    pod-security.kubernetes.io/enforce: restricted
    # Дополнительно просим предупреждать и писать в аудит
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/audit: restricted
EOF

# 2. Манифест безопасного пода (good-pod)
# Обратите внимание на секции securityContext
cat <<EOF > manifests/good-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: good-pod
  namespace: lab-restricted
spec:
  securityContext:
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: nginxinc/nginx-unprivileged:1.27-alpine
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
EOF

# 3. Манифест опасного пода (bad-pod)
# Отсутствует securityContext. По умолчанию запустится как root.
cat <<EOF > broken/scenario-01/bad-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: bad-pod
  namespace: lab-restricted
spec:
  containers:
  - name: app
    image: nginx:latest
EOF
```

Применим неймспейс:
```bash
kubectl apply -f manifests/restricted-ns.yaml
kubectl get ns lab-restricted --show-labels
```

Попытаемся создать плохой под:
```bash
kubectl apply -f broken/scenario-01/bad-pod.yaml
```
**ОЖИДАЕМЫЙ ВЫВОД (ОШИБКА):**
```text
Error from server (Forbidden): error when creating "broken/scenario-01/bad-pod.yaml":
  pods "bad-pod" is forbidden: violates PodSecurity "restricted:latest":
  allowPrivilegeEscalation != false (container "app" must set allowPrivilegeEscalation=false), 
  unrestricted capabilities (container "app" must set securityContext.capabilities.drop=["ALL"]),
  runAsNonRoot != true (pod or container "app" must set securityContext.runAsNonRoot=true), 
  seccompProfile (pod or container "app" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
```
*Обратите внимание: API-сервер заботливо перечисляет ВСЕ нарушения, которые он нашел. Это буквально инструкция для разработчика, что нужно исправить.*

Создадим хороший под:
```bash
kubectl apply -f manifests/good-pod.yaml
kubectl -n lab-restricted get pod good-pod
# good-pod   1/1   Running
```
Идеально. Под запущен и защищен на уровне ядра.

### 1.6 Стратегия безопасной миграции: warn и audit на проде

В реальной жизни вы не можете просто пойти и повесить `enforce: restricted` на `default` или рабочий namespace. Все поды разработчиков без securityContext немедленно перестанут деплоиться, и у вас будет инцидент.

Как внедрять PSA безопасно?
Kubernetes позволяет комбинировать метки. У PSA есть три режима:
- `enforce` — блокирует несоответствующие поды.
- `warn` — под создается, но разработчик в консоли видит желтый Warning.
- `audit` — под создается молча, но в `/var/log/audit/kube-apiserver-audit.log` пишется событие нарушения, которое парсится SIEM-системами.

**Практика миграции:**
```bash
# Применим только warn на обычный неймспейс lab
kubectl label ns lab pod-security.kubernetes.io/warn=restricted --overwrite

# Попытаемся запустить там дефолтный Nginx
kubectl -n lab run warn-pod --image=nginx:latest
```
**ОЖИДАЕМЫЙ ВЫВОД:**
```text
Warning: would violate PodSecurity "restricted:latest": allowPrivilegeEscalation != false (container "warn-pod" must set allowPrivilegeEscalation=false)...
pod/warn-pod created
```
Под **создан** (`pod/warn-pod created`), приложение работает. Но мы предупредили владельца, что в будущем этот манифест перестанет работать, когда мы включим `enforce`.

Удалим тестовый под:
```bash
kubectl -n lab delete pod warn-pod
```

### 1.7 Управление версионированием политик (enforce-version)

Стандарты Kubernetes меняются. То, что сегодня считается `restricted`, завтра может стать еще строже. Если вы обновите кластер с 1.25 до 1.30, правила PSA могут измениться под капотом, и ваш старый "идеальный" манифест вдруг начнет блокироваться.

Чтобы этого избежать, PSA поддерживает явное версионирование. В метках вы могли заметить: `restricted:latest`.
Вы можете зафиксировать версию правил (pinned version):
```bash
kubectl label ns lab pod-security.kubernetes.io/enforce-version=v1.27 --overwrite
```
Это гарантирует, что к неймспейсу будут применяться правила `restricted` точно так, как они были описаны в Kubernetes 1.27, даже если вы обновите кластер до 1.30+. Это защищает инфраструктуру от неожиданных поломок при апгрейдах кластера.

---

## Часть 2: ValidatingAdmissionPolicy (CEL)

### 2.1 Теория: Эволюция кастомных политик и введение в VAP

PSA идеален для базовой безопасности. Но что если нам нужна **бизнес-логика**?
- "Обязательно указывать label `environment: prod` или `environment: dev`".
- "Запретить образы из DockerHub, использовать только внутренний Registry `harbor.mycompany.com`".
- "Запретить тег `:latest` у образов".
- "Требовать, чтобы `requests` были равны `limits` (Guaranteed QoS)".

Исторически для этого писали **Validating Admission Webhooks**.
Архитектура вебхука: Kube-apiserver приостанавливает запрос, открывает HTTP(s) соединение, делает сетевой POST-запрос с JSON-объектом в ваш микросервис. Ваш микросервис (написанный на Go, Python или Java) разбирает JSON, принимает решение и отвечает HTTP 200 (Allow) или 403 (Deny).
**Проблемы вебхуков:**
1. Вы обязаны поддерживать TLS-сертификаты.
2. Вы обязаны деплоить под с вебхуком в HA (минимум 2 реплики).
3. Сетевые задержки.
4. **Катастрофический отказ:** Если вебхук "упадет" (OOM, сбой сети), а его `failurePolicy` стоит в `Fail`, Kubernetes перестанет создавать объекты. Ваш кластер окаменеет.

**ValidatingAdmissionPolicy (VAP)** — это встроенная замена вебхукам, GA с k8s 1.30.
VAP позволяет писать сложные правила валидации прямо в YAML с помощью языка **CEL**. 
- Выполняется in-process внутри `kube-apiserver`. Нулевые сетевые задержки.
- Не может "упасть", так как нет отдельного микросервиса.
- Чрезвычайно быстрый (компилируется в байткод).

### 2.2 Основы языка CEL (Common Expression Language) для Kubernetes

CEL — это легковесный, быстрый и безопасный язык выражений, созданный Google. Он не имеет циклов `for` в классическом понимании (чтобы избежать бесконечного выполнения) и не имеет доступа к сети. Он берет на вход данные (например, JSON-объект пода) и всегда возвращает `true` или `false`.

**Важнейшие макросы и операторы CEL для VAP:**
- `object` — переменная, содержащая текущий проверяемый Kubernetes объект.
- `has(object.metadata.labels)` — проверяет наличие поля, чтобы не получить ошибку NullPointerException.
- `.all(x, ...)` — аналог `for each`. Проверяет, что *для всех* элементов в списке выполняется условие.
- `.exists(x, ...)` — проверяет, что *хотя бы один* элемент в списке удовлетворяет условию.
- `matches('regex')` — проверка по регулярному выражению.
- `in` — проверка вхождения в словарь/список (например, `'owner' in object.metadata.labels`).

Пример: "Все контейнеры пода должны иметь CPU requests".
```cel
object.spec.containers.all(c, has(c.resources) && has(c.resources.requests) && has(c.resources.requests.cpu))
```

### 2.3 Архитектура VAP: Policy и Binding

Функционал разделен на два Cluster-Scoped объекта:
1. `ValidatingAdmissionPolicy` — само правило. Содержит CEL выражение и `matchConstraints` (к каким ресурсам это вообще применимо, например, только к Pods).
2. `ValidatingAdmissionPolicyBinding` — привязка. Связывает Policy с конкретными неймспейсами и задает действие (`validationActions: Deny | Warn | Audit`).

Зачем? Чтобы мы могли написать политику "Требовать ResourceLimits" один раз, а привязать ее к `namespace: dev` с действием `Warn` (просто информировать), а к `namespace: prod` с действием `Deny` (жестко блокировать).

### 2.4 Практика: Запрет использования тега :latest

Использование тега `:latest` — ужасная практика. Завтра образ обновится, и ваш под при рестарте скачает новую версию, ломая приложение. Зафиксируем это запретом.

```bash
cat <<EOF > manifests/vap-no-latest.yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata: 
  name: no-latest-tag
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
    - apiGroups:   [""]
      apiVersions: ["v1"]
      operations:  ["CREATE", "UPDATE"]
      resources:   ["pods"]
  validations:
  # Проходимся по всем контейнерам. 
  # Образ должен иметь тег (есть двоеточие) И этот тег не latest. ЛИБО это sha256 хеш.
  - expression: "object.spec.containers.all(c, (c.image.matches('^.*:[a-zA-Z0-9_.-]+$') && !c.image.matches('^.*:latest$')) || c.image.matches('^.*@sha256:[a-f0-9]+$'))"
    message: "ОШИБКА ИБ: Образы с тегом :latest или без тега запрещены! Укажите конкретный тег версии (например :1.27)."
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: no-latest-tag-binding
spec:
  policyName: no-latest-tag
  validationActions: [Deny]
  matchResources:
    namespaceSelector:
      matchLabels: 
        kubernetes.io/metadata.name: lab
EOF

kubectl apply -f manifests/vap-no-latest.yaml
```

Проверим политику в действии:

```bash
# Под с :latest в lab — ОТКЛОНЁН:
kubectl -n lab run bad --image=nginx:latest --restart=Never
# ОЖИДАЕМЫЙ ВЫВОД:
# Error from server (Forbidden): ... ValidatingAdmissionPolicy 'no-latest-tag' with binding 'no-latest-tag-binding' denied request: ОШИБКА ИБ: Образы с тегом :latest или без тега запрещены!

# Под без тега вообще (k8s считает это latest) — ОТКЛОНЁН:
kubectl -n lab run bad-notag --image=nginx --restart=Never

# Под с конкретным тегом — проходит успешно:
kubectl -n lab run good-tag --image=nginx:1.27-alpine --restart=Never
# pod/good-tag created

kubectl -n lab delete pod good-tag --ignore-not-found
```

### 2.5 Практика: Валидация обязательных меток (labels) и аннотаций

Требование наличия метаданных — классика эксплуатации (для биллинга, маршрутизации алертов). Потребуем обязательную метку `owner`.

```bash
cat <<EOF > manifests/vap-labels.yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: require-owner-label
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
    - apiGroups: [""]; apiVersions: ["v1"]; operations: ["CREATE", "UPDATE"]; resources: ["pods"]
  validations:
  # has() проверяет, что поле labels вообще существует (иначе будет ошибка CEL, если labels пуст)
  - expression: "has(object.metadata.labels) && 'owner' in object.metadata.labels"
    message: "Каждый под должен иметь метку 'owner' для биллинга!"
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: require-owner-label-binding
spec:
  policyName: require-owner-label
  validationActions: [Deny]
  matchResources:
    namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: lab
EOF

kubectl apply -f manifests/vap-labels.yaml

# Пытаемся создать под БЕЗ метки
kubectl -n lab run no-owner --image=nginx:1.27-alpine --restart=Never
# ОЖИДАЕМЫЙ ВЫВОД: (Forbidden) ... Каждый под должен иметь метку 'owner' для биллинга!

# Создаем под С меткой
kubectl -n lab run with-owner --image=nginx:1.27-alpine --labels="owner=devops-team" --restart=Never
# pod/with-owner created

kubectl -n lab delete pod with-owner --ignore-not-found
```

### 2.6 Практика: Продвинутая логика — ограничение hostPort

Иногда разработчики пытаются забиндить порт прямо на ноду через `hostPort`, что может вызвать конфликты. Запретим использовать "привилегированные" порты (< 1024) на нодах.

```yaml
# Пример сложного CEL выражения для изучения:
expression: >
  !has(object.spec.containers) || 
  object.spec.containers.all(c, 
    !has(c.ports) || 
    c.ports.all(p, 
      !has(p.hostPort) || p.hostPort >= 1024
    )
  )
```
Это выражение безопасно проверяет наличие всех вложенных структур, не падая с ошибкой, если `ports` не определены.

---

## Часть 3: Policy engines (Kyverno / OPA Gatekeeper) — обзор и глубокое погружение

### 3.1 Когда VAP недостаточно? (Сценарии Mutation и Generation)

Мы выяснили, что VAP отлично справляется с задачей "сказать НЕТ" (Validate).
Но VAP **абсолютно не умеет изменять (Mutate) или создавать (Generate) объекты**.

В каких реальных задачах DevOps инженеру нужны Policy Engines?
1. **Мутация по умолчанию (Mutation):** Если разработчик не указал класс хранилища (StorageClass) в PVC, автоматически подставить `storageClassName: "fast-ssd"`. Если разработчик не указал `imagePullPolicy`, принудительно выставить `Always`.
2. **Генерация объектов (Generation):** Как только в кластере создается новый Namespace, автоматически создать внутри него `NetworkPolicy`, `LimitRange` и дефолтный `RoleBinding` для группы "developers". Это автоматизирует процесс выдачи неймспейсов (Namespace-as-a-Service).
3. **Безопасность Supply Chain (Verify Images):** Проверка криптографической подписи образа контейнера (через Cosign или Notary) перед запуском. Подписан ли этот образ пайплайном Jenkins?

Для этих задач устанавливают внешние движки: OPA Gatekeeper или Kyverno.

### 3.2 Архитектура OPA Gatekeeper (Rego)

OPA (Open Policy Agent) — это универсальный движок политик уровня CNCF Graduated. OPA Gatekeeper — это его адаптация специально для Kubernetes.

- **Язык**: **Rego**. Это декларативный логический язык. Он мощный, но имеет высокий порог входа.
- **Модель**: Состоит из `ConstraintTemplate` (шаблон логики на Rego) и `Constraint` (параметры, применяемые к шаблону, например, список запрещенных меток).

*Пример валидации на Rego (требование метки):*
```rego
violation[{"msg": msg}] {
  provided_labels := {label | input.review.object.metadata.labels[label]}
  required_labels := {label | label := input.parameters.labels[_]}
  missing := required_labels - provided_labels
  count(missing) > 0
  msg := sprintf("you must provide labels: %v", [missing])
}
```
Как видите, Rego требует изучения. Это отличный выбор, если ваша компания уже использует OPA для Terraform, Envoy или API-шлюзов.

### 3.3 Архитектура Kyverno (YAML-native)

Kyverno (в переводе с греческого "управлять") был создан специально для Kubernetes. Его главная философия: **Никаких новых языков программирования. Политики — это просто YAML.**

*Пример Мутирующей политики Kyverno (Mutation), которая добавляет метку всем подам:*
```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: add-labels
spec:
  rules:
  - name: add-env-label
    match:
      resources:
        kinds:
        - Pod
    mutate: # Указание на мутацию
      patchStrategicMerge:
        metadata:
          labels:
            +(environment): "production"  # Знак + означает "добавить, если нет"
```
Kyverno значительно проще в освоении для Kubernetes инженеров и имеет огромную встроенную библиотеку политик для PSS, мутаций и генераций.

### 3.4 Сравнительная таблица и рекомендации по выбору

| Критерий | Kyverno | OPA Gatekeeper | Встроенные PSA + VAP |
|---|---|---|---|
| Изучение | Низкий порог (YAML) | Высокий порог (Rego) | Средний (нужно знать CEL) |
| Генерация (Создание объектов) | Да (отлично работает) | Нет (не фокус продукта) | Нет |
| Мутация | Да | Да (но синтаксис мутации сложен) | Нет |
| Производительность | Средняя (вебхук) | Высокая (но это вебхук) | Сверхвысокая (in-process) |
| Поддержка Verify Images | Да (встроенная интеграция с Cosign) | Да (Ratify / External Data) | Планируется (ImageVerify) |

**Рекомендация архитектора:**
Не тащите в кластер Kyverno или OPA, если вам нужно просто запретить `:latest` или включить `restricted`. Используйте **PSA + VAP**.
Внедряйте **Kyverno**, только если у вас появилась явная бизнес-задача на *автоматическую мутацию* или *генерацию* ресурсов (например, автоматическая выдача `NetworkPolicy` на каждый новый namespace).

---

## Часть 4: Troubleshooting (Углубленный дебаггинг)

Ошибки Admission Control — самые пугающие для новичков, потому что `kubectl apply` выдает огромное полотно красного текста с `Forbidden`. Давайте разберемся, как это читать.

### 4.1 Теория: Строгий порядок конвейера Admission Control

Ключ к решению любых конфликтов политик — понимание того, в каком порядке `kube-apiserver` пропускает объект через плагины. Этот порядок жестко зашит в код k8s:

```text
1. [AuthN/AuthZ] -> Пользователь имеет права RBAC создать Pod? (Да).
2. [Mutating Webhooks] -> Опрос ВСЕХ зарегистрированных мутаторов (Kyverno, Istio, Vault).
   Здесь объект ИЗМЕНЯЕТСЯ. Например, Istio добавляет контейнер 'istio-proxy'.
3. [Object Schema Validation] -> Объект соответствует OpenAPI схеме? Нет опечаток в полях?
4. [Validating Admission] -> Параллельный опрос всех валидаторов:
   ├── PSA (Pod Security Admission)
   ├── VAP (ValidatingAdmissionPolicy)
   └── Validating Webhooks (Gatekeeper, Kyverno Validate)
5. [Сохранение] -> Если ВСЕ сказали "Да", объект пишется в etcd.
```

**Золотое правило дебага:** 
Этап 4 (Валидация, включая PSA и VAP) видит объект **ПОСЛЕ** того, как он прошел этап 2 (Мутация).
Если PSA ругается на контейнер или поле, которого вы не писали в своем манифесте — значит, его добавил Mutating Webhook на этапе 2.

Как посмотреть объект после мутации, не сохраняя его в базу?
```bash
kubectl apply -f pod.yaml --dry-run=server -o yaml
```
Флаг `--dry-run=server` прогонит объект через этапы 1-3 и вернет вам итоговый манифест. Именно этот манифест валидируют PSA и VAP.

### 4.2 Как читать отказы: определяем виновника по тексту

Когда вы видите `Error from server (Forbidden)`, ищите ключевые слова, чтобы понять, КТО именно вас заблокировал:

| Ключевое слово в ошибке | Кто заблокировал? | Где чинить? |
|---|---|---|
| `violates PodSecurity "restricted:..."` | **PSA** | В манифесте пода (добавить securityContext) или ослабить профиль Namespace. |
| `ValidatingAdmissionPolicy 'NAME' with binding 'BINDING' denied...` | **VAP (CEL)** | Нарушено кастомное CEL правило. Читаем политику `kubectl get vap <NAME>`. |
| `admission webhook "NAME" denied the request...` | **Внешний Webhook** | Идем в логи Kyverno/Gatekeeper или смотрим их политики. |
| `is forbidden: User "X" cannot create resource...` | **RBAC (AuthZ)** | У вас нет прав. Нужно создавать `Role` и `RoleBinding`. |

### 4.3 Инцидент 1: Под отклонён PSA (restricted) — пошаговое исправление

**Ситуация:** Вы делаете `kubectl run test --image=nginx` в неймспейсе с `enforce: restricted`.
**Ошибка:** `violates PodSecurity "restricted:latest": allowPrivilegeEscalation != false, unrestricted capabilities...`
**Как исправить разработчику:**
Не пытайтесь "обойти" систему. Откройте манифест и добавьте необходимые поля ИМЕННО так, как просит ошибка.
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test
spec:
  securityContext:
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: test
    image: nginx
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
```
*Примечание: Официальный образ `nginx` из DockerHub запускается от root по умолчанию и упадет с ошибкой (CreateContainerError), даже если вы пропишете эти политики, потому что процесс внутри образа ожидает root-прав. Используйте `nginxinc/nginx-unprivileged`.*

### 4.4 Инцидент 2: Легитимный под не создаётся из-за VAP (Ложноположительное срабатывание)

**Ситуация:** Инженеры платформы выкатили VAP, и внезапно ваш CI/CD пайплайн перестал деплоить легитимный микросервис.
**Диагностика:** Ошибка гласит: `ValidatingAdmissionPolicy 'require-owner-label' ... denied request`.
**Решение:**
Если вы разработчик — добавьте метку `owner` в ваш Helm chart или YAML.
Если вы админ платформы и понимаете, что политика слишком жесткая, вы можете быстро перевести её в режим аудита, не удаляя правило:
```bash
# Редактируем Binding
kubectl edit validatingadmissionpolicybinding require-owner-label-binding
# Находим поле validationActions:
# validationActions:
# - Deny
# Меняем на:
# validationActions:
# - Warn
```
Теперь деплои пройдут, а разработчики получат предупреждения (Warnings).

### 4.5 Инцидент 3: Опасные поды проникают в кластер (PSA «не срабатывает»)

**Ситуация:** Вы повесили на неймспейс профиль, запустили привилегированный под, и он успешно создался! Почему?
**Возможные причины:**
1. **Опечатка в Label.** Метка должна быть `pod-security.kubernetes.io/enforce: restricted`. Если вы напишете `podsecurity.kubernetes.io` (без дефиса) или `restricted` с опечаткой, apiserver её **проигнорирует** и откатится к профилю по умолчанию (часто это `privileged`).
2. **Static Pods.** Вы тестируете защиту, создав файл в `/etc/kubernetes/manifests` на ноде. Static Pods читаются напрямую компонентом kubelet, минуя API-сервер и весь конвейер Admission Control. PSA на них не работает!

### 4.6 Инцидент 4: Конфликт Mutating Webhook Service Mesh и PSA

**Ситуация:** Ваш под идеально соответствует `restricted`. Но при деплое PSA его отклоняет, ругаясь на контейнеры `istio-init` или `istio-proxy`, которых вы не писали в манифесте!
**Причина (см. 4.1):** Mutating Webhook от Istio (Service Mesh) автоматически вставил (injected) sidecar-контейнеры в ваш под на этапе 2. Эти sidecar-контейнеры требуют `NET_ADMIN` capabilities или запуска от root для перенаправления iptables трафика. Затем на этапе 4 PSA видит этот измененный под, обнаруживает `NET_ADMIN` и блокирует его.
**Решение:**
- Конфигурация Service Mesh (например, включение Istio CNI plugin, который убирает необходимость в root `istio-init` контейнере).
- Понижение уровня PSA для данного конкретного namespace до `baseline`.

### 4.7 Инцидент 5: Ошибки синтаксиса CEL и дебаг выражений

Если вы написали сложное CEL выражение в VAP, которое содержит синтаксическую ошибку или обращается к несуществующему полю без проверки `has()`, политика может сломаться в рантайме.
В `ValidatingAdmissionPolicy` есть поле `failurePolicy`.
- Если `failurePolicy: Fail` — любая ошибка при вычислении CEL заблокирует создание объекта.
- Если `failurePolicy: Ignore` — при ошибке вычисления CEL объект будет пропущен (создан).
Для отладки сложных выражений рекомендуется начинать с `Warn` actions и внимательно читать логи `kube-apiserver`.

---

## Проверка модуля

Запустим скрипт проверки, чтобы убедиться, что все правила настроены корректно в вашем кластере:

```bash
# Применим финальные манифесты для чистоты
kubectl apply -f manifests/restricted-ns.yaml
kubectl apply -f manifests/good-pod.yaml
kubectl apply -f manifests/vap-no-latest.yaml
kubectl apply -f manifests/vap-labels.yaml

bash verify/verify.sh
```
**ОЖИДАЕМЫЙ РЕЗУЛЬТАТ В КОНСОЛИ:**
```text
[OK] PSA restricted enforced on lab-restricted
[OK] good-pod is Running
[OK] VAP no-latest present
[OK] VAP require-owner-label present
[OK] module 14 verified
```
Скрипт проверяет наличие Namespace, успешную работу эталонного пода и наличие настроенных VAP политик.

---

## Финальная карта ресурсов модуля

| Ресурс / Файл | Механизм | Архитектурный смысл |
|--------|----------|-------------------|
| Namespace `lab-restricted` | Pod Security Admission | Точка применения профиля (граница действия PSA). Использование меток `enforce`, `warn`, `audit`. |
| Pod `good-pod.yaml` | Манифест пода | Эталонный дизайн `securityContext` для Cloud-Native приложений в жестких корпоративных средах. |
| Pod `bad-pod.yaml` | Манифест пода | Пример нарушения стандартов. Не пройдет дальше API-сервера. |
| Policy `no-latest-tag` | ValidatingAdmissionPolicy (CEL) | Глобальный запрет небезопасных антипаттернов без поднятия внешней инфраструктуры вебхуков. |
| Policy `require-owner` | ValidatingAdmissionPolicy (CEL) | Пример реализации бизнес-требований компании (биллинг/ответственность) на уровне API Kubernetes. |

---

## Теоретические вопросы (итоговые)

1. **Контейнерная изоляция:** Почему запуск процесса в Docker-контейнере от имени `root` представляет угрозу безопасности для всего физического сервера (ноды)?
2. **PSS:** Назовите три официальных стандарта (профиля) Pod Security. Каким типам рабочих нагрузок соответствует каждый из них?
3. **PSA:** На каком этапе обработки запроса в Kubernetes API происходит отклонение пода механизмом PSA? Почему под даже не записывается в etcd?
4. **PSA vs PSP:** Назовите две главные причины, по которым разработчики Kubernetes решили полностью удалить функционал PodSecurityPolicy (PSP) в версии 1.25.
5. **Миграция:** Почему стратегия внедрения безопасности через метки `warn` и `audit` является обязательной для production кластеров, прежде чем включать `enforce`?
6. **VAP:** Чем архитектурно `ValidatingAdmissionPolicy` (CEL) превосходит внешние `Validating Webhooks` с точки зрения надежности и задержек?
7. **Конвейер Admission:** Объясните парадокс: почему под, который в исходном YAML файле выглядел полностью безопасным, может быть заблокирован PSA с ошибкой о наличии опасных capabilities? (Подсказка: Mutating Webhooks).
8. **Policy Engines:** В каких трех сценариях возможностей VAP вам гарантированно не хватит, и вы будете вынуждены устанавливать Kyverno или OPA Gatekeeper?

---

## Практические задания (отработка)

> 🧑‍💻 **Самостоятельная работа**: Выполняйте задания на живом кластере. Пользуйтесь официальной документацией Kubernetes (kubernetes.io) и шпаргалкой в конце модуля.

1. **Базовая защита PSA:** 
   Создайте namespace `sec-test`. Включите на нем режим `enforce: restricted`.
   Выполните команду: `kubectl run test-shell --image=busybox --restart=Never -- sleep 3600`.
   Убедитесь, что команда завершается с ошибкой. Прочитайте внимательно текст ошибки.
   *Задание со звездочкой:* Модифицируйте эту команду (сохраните в yaml через `--dry-run=client -o yaml > pod.yaml`), добавьте необходимые секции `securityContext`, чтобы под `test-shell` успешно запустился в этом неймспейсе.

2. **Аудит и миграция:**
   Создайте namespace `legacy-app`. Запустите в нем под `legacy-nginx` с дефолтным образом `nginx` (от root).
   Примените на namespace метку `warn: restricted` и `audit: restricted`.
   Убедитесь, что уже запущенный под продолжает работать (не убит).
   Попробуйте пересоздать под `legacy-nginx`. Обратите внимание на вывод в консоли (Warning).

3. **Разработка VAP (CEL):**
   Напишите свою VAP на CEL, которая запрещает использование монтирования хостовых путей (`hostPath`) в томах (`volumes`).
   Создайте VAP (Policy) и Binding для неймспейса `lab`. 
   Проверьте работу, попытавшись создать под с `hostPath: { path: /var/run }`.

4. **Анализ пайплайна (Mutating vs Validating):**
   Сделайте "сухой прогон" пода через сервер: `kubectl apply -f manifests/good-pod.yaml --dry-run=server -o yaml`. 
   Сравните полученный вывод с вашим исходным `good-pod.yaml`. Обратите внимание на добавленные поля (например, default ServiceAccount, tolerations), которые добавили другие мутирующие плагины.

5. **Очистка кластера (КРИТИЧНО):** 
   VAP ресурсы являются cluster-scoped. Если вы оставите политику `require-owner-label`, она будет мешать вам в последующих лабораторных работах (так как будет требовать метку у всех подов в lab). 
   Выполните уборку (см. конец файла).

---

## Шпаргалка

```bash
# === Управление Pod Security Admission (PSA) ===
# Жесткая блокировка нарушителей (enforce)
kubectl label ns <namespace> pod-security.kubernetes.io/enforce=restricted --overwrite

# Только предупреждать пользователя в терминале (warn)
kubectl label ns <namespace> pod-security.kubernetes.io/warn=restricted --overwrite

# Только писать в аудит-логи apiserver (audit)
kubectl label ns <namespace> pod-security.kubernetes.io/audit=restricted --overwrite

# Зафиксировать версию правил (чтобы апгрейд k8s не сломал логику)
kubectl label ns <namespace> pod-security.kubernetes.io/enforce-version=v1.30 --overwrite

# Посмотреть текущие метки профилей на неймспейсе
kubectl get ns <namespace> -o jsonpath='{.metadata.labels}'
# или просто
kubectl get ns <namespace> --show-labels

# Проверить "сухим прогоном", не нарушат ли СУЩЕСТВУЮЩИЕ поды новый профиль
kubectl label --dry-run=server ns <namespace> pod-security.kubernetes.io/enforce=restricted


# === Управление ValidatingAdmissionPolicy (VAP) ===
# Посмотреть все политики и привязки в кластере
kubectl get validatingadmissionpolicy
kubectl get validatingadmissionpolicybinding

# Посмотреть детали и прочитать CEL выражение конкретной политики
kubectl describe validatingadmissionpolicy no-latest-tag

# Перевести политику из Deny в Warn (отредактировав Binding)
kubectl edit validatingadmissionpolicybinding no-latest-tag-binding


# === Дебаггинг конвейера ===
# Посмотреть, как будет выглядеть объект ПОСЛЕ Mutating Webhooks, но ДО сохранения
kubectl apply -f pod.yaml --dry-run=server -o yaml
```

---

## Чему вы научились

В этом глубоком техническом модуле вы научились:
- Понимать фундаментальные уязвимости контейнерной изоляции в Linux (общее ядро) и то, как `securityContext` закрывает эти векторы атак.
- Внедрять эшелонированную защиту кластера через Pod Security Standards и встроенный механизм Pod Security Admission (PSA).
- Планировать и применять стратегию мягкой миграции на строгие профили безопасности с использованием режимы `warn` и `audit`.
- Писать декларативные, сверхбыстрые in-process политики валидации (ValidatingAdmissionPolicy) на современном языке CEL прямо внутри Kubernetes, избегая накладных расходов на развертывание внешних вебхуков.
- Строить архитектурные границы применимости встроенных средств (PSA/VAP) по сравнению с тяжеловесными Policy Engines (Kyverno/OPA Gatekeeper).
- Мастерски дебажить Admission-конвейер Kubernetes, точно зная порядок выполнения (Мутация -> Схема -> Валидация) и умея читать тексты отказов.

## Уборка

Перед переходом к следующему модулю критически важно очистить стенд от cluster-scoped ресурсов (VAP политик), иначе они могут заблокировать выполнение других лабораторных работ, которые не ожидают таких строгих правил в неймспейсе `lab`.

```bash
# Удаляем кастомные VAP политики
kubectl delete -f manifests/vap-no-latest.yaml --ignore-not-found
kubectl delete -f manifests/vap-labels.yaml --ignore-not-found

# Удаляем тестовый Restricted неймспейс
kubectl delete ns lab-restricted --ignore-not-found

# Проверка, что VAP очищены
kubectl get validatingadmissionpolicy
```


## Решения (Solutions)
В данном модуле добавлены подробные решения для сломанных сценариев в папке `solutions/`. Пожалуйста, изучите их для лучшего понимания.
