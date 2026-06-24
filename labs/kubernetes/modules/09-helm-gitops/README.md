# Лабораторная работа 09: Helm и GitOps (Argo CD)

## Оглавление
<!-- TOC -->
- [Предварительные требования](#предварительные-требования)
- [Стартовая проверка](#стартовая-проверка)
- [Часть 1: Helm chart](#часть-1-helm-chart)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью)
  - [1.1 Lint и рендер](#11-lint-и-рендер)
  - [1.2 Установка release](#12-установка-release)
  - [1.3 Переопределение values и Rollback](#13-переопределение-values-и-rollback)
- [Часть 2: GitOps и Argo CD](#часть-2-gitops-и-argo-cd)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-1)
  - [Архитектура Argo CD в деталях](#архитектура-argo-cd-в-деталях)
  - [2.1 Application и AppProject](#21-application-и-appproject)
  - [2.2 Реальный прогон с Argo CD](#22-реальный-прогон-с-argo-cd)
  - [2.3 Практика автоматического восстановления (SelfHeal)](#23-практика-автоматического-восстановления-selfheal)
- [Часть 3: Troubleshooting](#часть-3-troubleshooting)
  - [Системная методология (по двум осям статуса)](#системная-методология-по-двум-осям-статуса)
  - [Инцидент 1: Argo CD не синхронизирует — неверный `path` (Unknown)](#инцидент-1-argo-cd-не-синхронизирует--неверный-path-unknown)
  - [Инцидент 2: Sync=Synced, Health=Degraded (CrashLoopBackOff)](#инцидент-2-syncsynced-healthdegraded-crashloopbackoff)
  - [Инцидент 3: Ошибка прав (SyncError - Forbidden)](#инцидент-3-ошибка-прав-syncerror---forbidden)
  - [Инцидент 4: Зависший Sync-hook (Progressing навсегда)](#инцидент-4-зависший-sync-hook-progressing-навсегда)
- [Часть 4: Управление секретами (SOPS + Helm Secrets)](#часть-4-управление-секретами-sops--helm-secrets)
  - [Как это работает](#как-это-работает)
  - [Альтернативные подходы](#альтернативные-подходы)
- [Проверка модуля](#проверка-модуля)
- [Финальная карта ресурсов модуля](#финальная-карта-ресурсов-модуля)
- [Теоретические вопросы (итоговые)](#теоретические-вопросы-итоговые)
- [Практические задания (отработка)](#практические-задания-отработка)
- [Шпаргалка](#шпаргалка)
- [Чему вы научились](#чему-вы-научились)
- [Уборка](#уборка)
- [Решения (Solutions)](#решения-solutions)
<!-- /TOC -->

> ⏱ время ~45 мин · сложность 3/5 · пререквизиты: Трек 1 (Core)

Цель: упаковать приложение в Helm chart и разворачивать его декларативно через
GitOps (Argo CD) — где Git является источником истины, а контроллер постоянно
выравнивает состояние кластера под репозиторий. К концу модуля вы рендерите
chart, ставите release, читаете причину sync-фейла и решаете инциденты.

---

## Предварительные требования

```bash
# kubeconfig нашего кластера (Kubespray); на другом стенде — свой путь/контекст
export KUBECONFIG=/root/.kube/kubespray.conf
# helm нужен для Части 1
helm version --short 2>/dev/null || echo "helm не установлен — поставьте для Части 1"
```

## Стартовая проверка

Убедитесь, что кластер доступен:
```bash
kubectl get nodes
```

```bash
# Argo CD (Часть 2) опционален: манифесты можно проверить dry-run и без него,
# но для РЕАЛЬНОГО sync нужен установленный Argo CD. Ставьте пиннутым скриптом
# (он использует --server-side, иначе большой CRD applicationsets не применится):
#   bash ../../scripts/bootstrap/06-install-argocd.sh
kubectl get ns argocd 2>/dev/null || echo "argocd не установлен — dry-run манифестов всё равно сработает"
```

---

## Часть 1: Helm chart

### Теория для изучения перед частью

**Почему именно Helm?**
В Kubernetes манифесты пишутся на статичном YAML. Когда у вас 10 окружений (dev, stage, prod), копировать папки с манифестами становится трудно поддерживать.
Helm — это пакетный менеджер для Kubernetes, который:
1. **Шаблонизирует:** Позволяет использовать переменные вместо жестко зашитых значений (например, количество реплик).
2. **Пакетирует:** Объединяет разрозненные YAML-файлы в единый логический пакет — *chart*.
3. **Управляет релизами:** Отслеживает версии установок, позволяя делать `rollback` (откат) на предыдущую работающую версию.

- **Chart** — параметризованный пакет манифестов: `Chart.yaml` (метаданные, зависимости),
  `values.yaml` (параметры по умолчанию), `templates/` (Go-template, рендерятся в YAML).
- **Поток:** `helm template`/`install` подставляет `.Values.*` и `.Release.*` в
  шаблоны. `helm lint` ловит ошибки ДО деплоя.
- **Release** — установленный экземпляр chart; обновляется идемпотентно через
  `helm upgrade --install`.

**Go-template — мини-справочник** (всё это реально есть в `templates/deployment.yaml`):

| Конструкция | Что делает | Где в chart |
|-------------|------------|-------------|
| `{{ .Values.x }}` | значение из `values.yaml` (или `--set`) | `replicas: {{ .Values.replicaCount }}` |
| `{{ .Release.Name }}` | имя релиза (из `helm install <name>`) | `name: {{ .Release.Name }}` |
| `{{ .Chart.Name }}` | имя chart из `Chart.yaml` | `app.kubernetes.io/name: {{ .Chart.Name }}` |
| `{{- if .Values.probes.enabled }}…{{- end }}` | условный блок (рендерится только если true) | блок probes; весь `ingress.yaml` |
| `{{- with .Values.securityContext }}…{{- end }}` | сменить контекст: внутри `.` = этот объект | блок securityContext |
| `{{ toYaml .Values.resources | indent 10 }}` | объект → YAML c отступом 10 пробелов | блок `resources:` |
| `{{-` … | срезать пробел/перевод строки слева (чистые отступы) | перед `if`/`with` |

```yaml
# фрагмент templates/deployment.yaml — видно, как values становятся манифестом
spec:
  replicas: {{ .Values.replicaCount }}          # <- .Values.replicaCount (1)
  template:
    spec:
      containers:
      - image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"   # nginx:1.27-alpine
        {{- if .Values.probes.enabled }}         # блок probes только если enabled
        readinessProbe: { httpGet: { path: {{ .Values.probes.readiness.path }}, port: http } }
        {{- end }}
        resources:
{{ toYaml .Values.resources | indent 10 }}        # объект resources как YAML
```

#### _helpers.tpl (Именованные шаблоны)
Для крупных chart'ов повторяющиеся куски (labels, имена, селекторы) выносят в именованные
шаблоны `_helpers.tpl` и подключают через `{{ include "name" . }}`. В этом
минимальном demo их НЕТ — labels продублированы прямо в шаблонах (так нагляднее).
Пример классического `_helpers.tpl`:
```gotemplate
{{/*
Expand the name of the chart.
*/}}
{{- define "demo-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}
```
Использование: `name: {{ include "demo-app.name" . }}`

- **Приоритет values (кто кого перебивает, слева направо — последнее ВЫИГРЫВАЕТ):**
  `values.yaml` chart'а  →  `-f my-values.yaml`  →  `--set key=val`.
  То есть `--set replicaCount=2` перебьёт и `values.yaml`, и `-f`. Несколько `-f`
  применяются по порядку; несколько `--set` — тоже (правый побеждает).

#### Helm-хуки: запуск действий вокруг install/upgrade

Хук — обычный манифест (чаще `Job`) с аннотацией `helm.sh/hook`. Helm вырывает
его из общего apply и запускает в нужный момент релиза — для миграций БД,
прогрева, бэкапа перед апгрейдом.

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migrate
  annotations:
    "helm.sh/hook": pre-upgrade,pre-install      # когда запускать
    "helm.sh/hook-weight": "-5"                  # порядок внутри фазы (меньше = раньше)
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
spec:
  template:
    spec:
      restartPolicy: Never
      containers: [{ name: migrate, image: myapp:1.0, command: ["./migrate.sh"] }]
```

| Хук | Когда | Типичная задача |
|---|---|---|
| `pre-install` | до рендера/apply ресурсов при первой установке | создать схему БД |
| `post-install` | после того как ресурсы созданы | прогрев, регистрация |
| `pre-upgrade` / `post-upgrade` | до / после `helm upgrade` | миграция БД, smoke-тест |
| `pre-delete` / `post-delete` | до / после `helm uninstall` | бэкап, очистка внешних ресурсов |
| `test` | по `helm test` | проверка живости релиза |

- **`hook-weight`** упорядочивает хуки одной фазы (целое, по возрастанию).
- **`hook-delete-policy`** убирает Job хука: `hook-succeeded` (после успеха),
  `before-hook-creation` (удалить прошлый перед новым запуском), `hook-failed`.
- **Helm ЖДЁТ** завершения хука (`Job` → `Complete`) перед следующей фазой; упавший
  `pre-upgrade` отменяет апгрейд. Это отличает хук от обычного `Job` в `templates/`,
  который применяется вместе со всем и не блокирует релиз.
- Argo CD НЕ исполняет Helm-хуки как Helm — он мапит их на свои фазы (см. ниже
  sync-waves/hooks).

---

**Цель:** проверить и установить chart `demo-app`.

**Ресурс:** `charts/demo-app/` (Deployment/Service/Ingress/ConfigMap + values).

---

### 1.1 Lint и рендер

Прежде чем устанавливать что-либо, всегда полезно провалидировать синтаксис:

```bash
helm lint ./charts/demo-app
# Ожидаемый вывод:
# ==> Linting ./charts/demo-app
# [INFO] Chart.yaml: icon is recommended
# 1 chart(s) linted, 0 chart(s) failed

# Рендерим шаблоны в stdout, чтобы увидеть, что именно отправится в кластер
helm template demo-app ./charts/demo-app | grep -E "kind:|image:|host:"
# kind: ConfigMap
# kind: Service
# kind: Deployment
# image: "nginx:1.27-alpine"
# kind: Ingress
# host: demo-app.local
```

### 1.2 Установка release

```bash
# --install говорит Helm установить chart, если релиза еще не существует
# --create-namespace создаст неймспейс, если его нет
helm upgrade --install demo-app ./charts/demo-app -n lab --create-namespace
# Ожидаемый вывод:
# Release "demo-app" does not exist. Installing it now.
# NAME: demo-app
# LAST DEPLOYED: <date>
# NAMESPACE: lab
# STATUS: deployed
# REVISION: 1
# TEST SUITE: None

kubectl -n lab get deploy,svc,ingress -l app.kubernetes.io/name=demo-app
```

### 1.3 Переопределение values и Rollback

Helm позволяет легко менять конфигурацию "на лету" без изменения файлов:

```bash
helm upgrade --install demo-app ./charts/demo-app -n lab \
  --set replicaCount=2 --set image.tag=1.27.5-alpine
```

Посмотрим историю изменений:
```bash
helm history demo-app -n lab
# REVISION  UPDATED                   STATUS      CHART           APP VERSION  DESCRIPTION
# 1         ...                       superseded  demo-app-0.1.0  1.0.0        Install complete
# 2         ...                       deployed    demo-app-0.1.0  1.0.0        Upgrade complete

kubectl -n lab get deploy demo-app -o jsonpath='{.spec.replicas}{"\n"}'   
# 2
```

Откатимся на предыдущую версию:
```bash
helm rollback demo-app 1 -n lab
# Rollback was a success! Happy Helming!

kubectl -n lab get deploy demo-app -o jsonpath='{.spec.replicas}{"\n"}'
# 1 (вернулись к исходному состоянию)
```

**Контрольные вопросы (Часть 1):**
1. В чем главное преимущество Helm перед Kustomize и сырым YAML?
2. Из каких обязательных частей состоит Helm chart?
3. Как `values.yaml` и `templates/` дают итоговый манифест?
4. Чем полезны `helm lint`/`helm template` до деплоя?
5. Почему `helm upgrade --install` считается лучшей практикой по сравнению с `helm install`?
6. Что произойдет, если мы сделаем rollback на несуществующую ревизию?

---

## Часть 2: GitOps и Argo CD

### Теория для изучения перед частью

**Что такое GitOps и почему это безопасно?**
Традиционный CI/CD (Push) работает так: GitLab CI собирает образ и выполняет `kubectl apply`. Для этого CI-сервер должен иметь учетные данные (kubeconfig) с широкими правами к кластеру Kubernetes.
GitOps (Pull) работает иначе: в кластере живет агент (Argo CD), который "тянет" изменения из Git. CI-сервер только собирает образ и обновляет тег в Git.
*Безопасность:* Кластеру больше не нужно открывать свой API наружу. Агент внутри кластера сам инициирует исходящее соединение к Git-репозиторию.

- **GitOps:** желаемое состояние в Git, контроллер (Argo CD/Flux) непрерывно
  сравнивает его с кластером и устраняет **drift** (ручные правки откатываются к
  Git). Деплой = коммит.
- **Argo CD `Application`** описывает ЧТО синхронизировать (`repoURL`, `path`,
  `targetRevision`, namespace) и КАК (`syncPolicy`: `automated`/`prune`/
  `selfHeal`). **`AppProject`** задаёт границы (репозитории, namespaces, ресурсы).

### Архитектура Argo CD в деталях

**(что реально стоит в ns `argocd`, v3.4.3 — 7 компонентов):**

```text
            Git (source of truth)
               │  репо + path + targetRevision
               ▼
   ┌──────────── ns argocd ─────────────────────────────────────────┐
   │  repo-server          → клонирует Git, РЕНДЕРИТ манифесты        │
   │                         (helm template / kustomize build)       │
   │                                                                 │
   │  application-controller→ сравнивает desired(Git) ↔ live(кластер),│ ──┐
   │                         считает sync/health, делает apply        │   │ kube-apiserver
   │                                                                 │   ▼
   │  redis                → кэш отрендеренного/diff и метаданных      │  ns lab (Deployment/Svc/…)
   │                                                                 │
   │  server (API/UI)      → отдает UI и REST API для CLI             │
   │  dex(SSO)             → интеграция с OIDC (GitLab/GitHub)        │
   │  applicationset       → контроллер генерации Application-ов      │
   │  notifications        → отправка алертов (Slack/Email)           │
   └─────────────────────────────────────────────────────────────────┘
```

**Sync-loop:** опрос Git каждые ~3 мин (или webhook) → repo-server рендерит →
controller диффит Git↔кластер. Совпало → `Synced`; разошлось → `OutOfSync` и (при
`automated`) `apply`. `selfHeal` реагирует на drift В КЛАСТЕРЕ (ручной `kubectl
edit/delete`) и возвращает к Git; `prune` удаляет из кластера то, что убрали из Git.

**Две независимые оси статуса** (их часто путают):

| Sync status | Значение | | Health status | Значение |
|-------------|----------|-|---------------|----------|
| `Synced` | кластер = Git | | `Healthy` | все ресурсы здоровы |
| `OutOfSync` | есть расхождение | | `Progressing` | ещё разворачивается / ждёт условие (Deploy не Available, Ingress без адреса) |
| `Unknown` | не смог сравнить (ошибка `path`/repo) | | `Degraded` | ресурс в ошибке (CrashLoop, failed) |
| | | | `Missing` | ресурс из Git отсутствует в кластере |

> Поэтому `Synced` + `Progressing` — нормальное промежуточное состояние, НЕ ошибка
> sync (как наш Ingress без контроллера: состояние совпало с Git, но ресурс не
> «дозрел» до Healthy).

#### Sync-waves и хуки Argo CD: порядок применения ресурсов

По умолчанию Argo CD применяет все ресурсы разом, но сложный деплой требует
ПОРЯДКА: CRD → namespace/ConfigMap → Deployment → миграция → Ingress. Порядок
задаёт аннотация `argocd.argoproj.io/sync-wave` (целое; меньше = раньше):

```text
wave -1: CustomResourceDefinition, Namespace   ◄── фундамент
wave  0: ConfigMap, Secret, ServiceAccount      (default, если аннотации нет)
wave  1: Deployment, StatefulSet, Service
wave  2: Ingress, HPA                            ◄── зависят от готового сервиса
```

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "1"
```

- **Внутри одной волны** Argo всё равно соблюдает встроенный порядок по kind
  (namespaces и CRD раньше потребителей). Волны добавляют ЯВНЫЙ порядок поверх.
- Argo ЖДЁТ, пока ресурсы текущей волны не станут **Healthy**, прежде чем перейти
  к следующей.
- **Sync-фазы и хуки Argo** (аналог Helm-хуков, аннотация `argocd.argoproj.io/hook`):
  `PreSync` (до основного sync — миграции), `Sync` (основная волна), `PostSync`
  (после Healthy — smoke-тест), `SyncFail` (если sync упал). `hook-delete-policy`
  убирает Job хука как в Helm.
- Helm-хуки чарта Argo CD КОНВЕРТИРУЕТ: `pre-install/pre-upgrade` → `PreSync`,
  `post-*` → `PostSync`, `test` → отдельно. Поэтому Helm-чарт с хуками работает и
  под Argo, но через его фазовую модель, а не через `helm`.

---

**Цель:** подготовить и провалидировать GitOps-манифесты.

**Ресурсы:** `gitops/argocd/{project,app}.yaml`.

---

### 2.1 Application и AppProject

```bash
# repoURL/path указывают на ЭТОТ репозиторий и chart:
grep -E "repoURL|path:|targetRevision" gitops/argocd/app.yaml
# repoURL: https://github.com/dedanimalfarm/lern.git
# targetRevision: main
# path: labs/kubernetes/modules/09-helm-gitops/charts/demo-app

# Валидация dry-run. Без установленных Argo CD CRDs kind не распознается — это
# ожидаемо для стенда без Argo CD:
kubectl apply --dry-run=client -f gitops/argocd/project.yaml
kubectl apply --dry-run=client -f gitops/argocd/app.yaml
# error: no matches for kind "Application" ... => Argo CD не установлен (ок)
```

### 2.2 Реальный прогон с Argo CD

Для чистоты эксперимента удалим Helm-релиз, созданный в Части 1:
```bash
helm uninstall demo-app -n lab
```

Теперь передадим управление Argo CD:
```bash
# 1) Поставить Argo CD (пиннутый, idempotent). ВАЖНО: server-side apply —
#    CRD applicationsets > 256KB не влезает в last-applied-аннотацию обычного apply.
bash ../../scripts/bootstrap/06-install-argocd.sh
# (под капотом: kubectl apply -n argocd --server-side -f .../v3.4.3/manifests/install.yaml)

# 2) Создать AppProject (границы) и Application (что/как синхронизировать)
kubectl apply -f gitops/argocd/project.yaml   # appproject.argoproj.io/labs
kubectl apply -f gitops/argocd/app.yaml        # application.argoproj.io/demo-app

# 3) Контроллер сам синхронизирует chart из Git в ns lab (syncPolicy.automated)
kubectl -n argocd get application demo-app \
  -o jsonpath='sync={.status.sync.status} health={.status.health.status} rev={.status.sync.revision}{"\n"}'
# sync=Synced health=Healthy rev=<sha>...   <- Synced = совпало с Git; Healthy = все ресурсы здоровы
```

> ✅ **Прогнано на нашем Kubespray-кластере (Argo CD v3.4.3):** Application `demo-app`
> → **Synced** с ревизии `main`; в ns `lab` появились Deployment/Service/ConfigMap/Ingress
> прямо из Git. Приложение реально отвечает: `wget -qO- http://demo-app/` →
> `<title>Welcome to nginx!</title>`. С установленным ingress-nginx Ingress
> получает ADDRESS (internal-IP ноды), и Application становится **Healthy**.

### 2.3 Практика автоматического восстановления (SelfHeal)

Argo CD способен не только устанавливать, но и защищать инфраструктуру от ручного вмешательства.
Проверим **selfHeal вживую (откат drift):**

```bash
# Сымитируем инцидент: удалим управляемый ресурс «руками».
# Допустим, неопытный администратор случайно удалил deployment
kubectl -n lab delete deploy demo-app

# Посмотрим статус приложения в Argo:
kubectl -n argocd get app demo-app -o jsonpath='{.status.sync.status}'
# Кратковременно мы можем увидеть OutOfSync

# Ждем ~10-20с...
# deployment снова есть и Ready=1/1 — контроллер устранил drift:
kubectl -n lab get deploy demo-app
```

> **Про health Ingress.** Argo CD считает Ingress Healthy только когда у него есть
> `status.loadBalancer.ingress` (ADDRESS). У нас стоит **ingress-nginx** (baremetal,
> с `--report-node-internal-ip-address`, см. `scripts/bootstrap/03-install-ingress.sh`),
> поэтому Ingress `demo-app` получает internal-IP ноды и Application — `Healthy`.
> ⚠️ Если ingress-controller НЕ установлен (или это cloud-вариант с LB в `<pending>`),
> Ingress останется без адреса, и Application честно зависнет в `Progressing` — это НЕ
> сбой GitOps (`sync=Synced`, workload Healthy), а лишь «недозревший» Ingress. Тогда —
> поставить контроллер или `helm.parameters: ingress.enabled=false`.
> `prune: true` удалит из кластера то, что убрали из Git (полный GitOps).

**Контрольные вопросы (Часть 2):**
1. Что является source of truth в GitOps и как идёт деплой?
2. Почему GitOps (Pull модель) считается безопаснее традиционного CI (Push модели)?
3. Что такое drift и как `selfHeal` его устраняет?
4. Роли `Application` и `AppProject`? Зачем вообще нужен AppProject?
5. Что делает `prune: true`? Если его отключить, что произойдет при удалении файла из Git?

---

## Часть 3: Troubleshooting

### Системная методология (по двум осям статуса)

Не угадывать, а читать sync и health — они указывают РАЗНЫЕ классы проблем:

```text
kubectl -n argocd get application <app>        # 1) посмотреть SYNC и HEALTH
        │
        ├─ SYNC=Unknown / OutOfSync ──> проблема СРАВНЕНИЯ/рендера (Git, не кластер):
        │     kubectl -n argocd get application <app> -o jsonpath='{.status.conditions}'
        │     # ComparisonError -> неверный path/repoURL/targetRevision
        │     # логи рендера:  kubectl -n argocd logs deploy/argocd-repo-server | tail
        │
        └─ SYNC=Synced, но HEALTH ≠ Healthy ──> проблема САМОГО РЕСУРСА в кластере:
              ├─ Degraded     -> ресурс в ошибке: kubectl -n <dest-ns> describe <res>
              │                   (CrashLoop, ErrImagePull, failed Job …)
              └─ Progressing  -> какой ресурс «не дозрел»: смотри его условия
                  # частая причина: Deployment не Available, Ingress без адреса
                  # логи самого sync: kubectl -n argocd logs sts/argocd-application-controller
```

**Опционально через `argocd` CLI** (если поставлен бинарь и сделан `argocd login`):

```bash
argocd app get demo-app          # дерево ресурсов + sync/health построчно
argocd app diff demo-app         # ЧЕМ кластер отличается от Git (до sync)
argocd app sync demo-app         # принудительная синхронизация
argocd app logs demo-app         # логи приложения через Argo CD
```

> Без CLI всё то же доступно через `kubectl -n argocd get application <app> -o yaml`
> (раздел `.status`: `sync`, `health`, `resources[]`, `conditions[]`).

---

### Инцидент 1: Argo CD не синхронизирует — неверный `path` (Unknown)

Оформлен в `broken/scenario-01/`: `spec.source.path` указывает на несуществующий
`charts/wrong-path`.

**Диагностика:**
```bash
kubectl apply -f broken/scenario-01/app.yaml
kubectl -n argocd get application demo-app
# SYNC STATUS: Unknown   HEALTH: Missing      <- манифесты не найдены
kubectl -n argocd get application demo-app -o jsonpath='{.status.conditions}'
# ... "ComparisonError" ... path '.../charts/wrong-path' does not exist
```
*Суть:* Ошибка на фазе клонирования и сборки манифестов `repo-server`. ArgoCD даже не пытается применить это в кластер.

**Решение:**
```bash
kubectl apply -f solutions/01-argocd-path/app.yaml   # path -> .../charts/demo-app
```

---

### Инцидент 2: Sync=Synced, Health=Degraded (CrashLoopBackOff)

Вы случайно закоммитили образ с опечаткой (например `image: nginxxxx:latest`) или приложение падает при старте (отсутствует переменная окружения).

**Диагностика:**
```bash
# Argo CD покажет:
# SYNC STATUS: Synced    HEALTH: Degraded
```
*Суть:* Манифесты в кластере 1-в-1 соответствуют Git. Argo CD свою работу сделал идеально (Sync=Synced). Проблема внутри самого кластера — Kubernetes не может запустить под.

**Решение:**
Здесь Argo CD не помощник. Нужно использовать стандартные инструменты `kubectl`:
```bash
kubectl -n lab get pods
# demo-app-85b88c...   0/1     ErrImagePull   0          12s
kubectl -n lab describe pod -l app.kubernetes.io/name=demo-app
```
Затем исправить опечатку в `values.yaml`, закоммитить в Git, и Argo CD обновит ресурс.

---

### Инцидент 3: Ошибка прав (SyncError - Forbidden)

Вы пытаетесь задеплоить `ClusterRole` или создать `Namespace`, но у AppProject, в котором находится Application, нет на это прав, либо у сервисного аккаунта Argo CD нет прав в кластере.

**Диагностика:**
```bash
kubectl -n argocd get application demo-app
# SYNC STATUS: SyncFailed    HEALTH: Missing/Progressing
```
При просмотре событий или условий мы увидим:
```text
failed to sync clusterrole "my-role": clusterroles.rbac.authorization.k8s.io is forbidden: User "system:serviceaccount:argocd:argocd-application-controller" cannot create resource "clusterroles" at the cluster scope
```
*Суть:* Application-controller работает от своего ServiceAccount. Если вы пытаетесь управлять кластерными ресурсами (ClusterRole, Namespace), Argo CD должен быть настроен на кластерный уровень, а AppProject должен разрешать ClusterResource `*/*`.

---

### Инцидент 4: Зависший Sync-hook (Progressing навсегда)

Вы добавили Helm-hook `pre-install` для миграции базы данных, но скрипт завис.

**Диагностика:**
```bash
# SYNC STATUS: Synced    HEALTH: Progressing
```
*Суть:* Argo CD запустил Job с хуком `PreSync`. Пока этот Job не завершится (статус `Complete`), Argo CD не перейдет к фазе `Sync` и не создаст Deployment.
Решение — смотреть логи Job'а миграции:
```bash
kubectl -n lab get jobs
kubectl -n lab logs -l job-name=migrate-db
```

**Контрольные вопросы (Troubleshooting):**
1. В каком случае мы увидим Sync Status = `Unknown`?
2. Почему ошибка `ImagePullBackOff` не переводит приложение в статус `OutOfSync`?
3. Где искать логи, если в `status.conditions` написано `ComparisonError`?
4. Как понять, что процесс синхронизации остановился из-за зависшего хука миграции?

---

## Часть 4: Управление секретами (SOPS + Helm Secrets)

GitOps требует хранения всех манифестов в Git, но хранить секреты в открытом виде или в Base64 (как в обычных `Secret`) категорически небезопасно. Решение — шифровать секреты перед коммитом и расшифровывать их прямо перед деплоем. Одно из популярных решений для этого — SOPS (Secrets OPerationS) от Mozilla совместно с плагином Helm Secrets.

SOPS позволяет шифровать значения (values) в YAML-файлах, оставляя ключи видимыми для понимания структуры. В качестве ключей шифрования могут выступать PGP, AWS KMS, GCP KMS или Azure Key Vault.

### Как это работает

1. Администратор зашифровывает файл (например, `secrets.yaml` -> `secrets.enc.yaml`) с помощью SOPS и нужного ключа.
2. Зашифрованный файл безопасно коммитится в Git. Пример:
   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: my-secret
   stringData:
     db-password: ENC[AES256_GCM,data:Y8a12...,iv:...,tag:...,type:str]
   sops:
     kms: []
     gcp_kms: []
     pgp:
       - created_at: "2023-10-01T12:00:00Z"
         fp: F3B52...
   ```
3. Argo CD (или CI/CD pipeline), используя плагин Helm Secrets и закрытый ключ, расшифровывает файл **только в памяти** прямо перед вызовом `helm template` или `helm install`.
4. В кластер секрет попадает в расшифрованном виде как обычный Kubernetes `Secret`.

### Альтернативные подходы

В современной практике SOPS все чаще заменяют на **External Secrets Operator (ESO)**. В этом подходе в Git хранятся не зашифрованные секреты, а только "указатели" (`ExternalSecret`), которые говорят контроллеру в кластере сходить в HashiCorp Vault, AWS Secrets Manager или Yandex Lockbox, взять оттуда настоящий секрет и положить его в Kubernetes `Secret`. Это снимает необходимость управлять PGP ключами на стороне Argo CD.

В нашей лаборатории Argo CD плагины для SOPS не настроены, поэтому мы не будем выполнять деплой зашифрованных секретов, но понимание этой концепции критически важно для Production-окружений.

---

## Проверка модуля

```bash
bash verify/verify.sh
# ==> Linting charts/demo-app ... 0 chart(s) failed   (если есть helm)
# [WARN] argocd CRDs not installed — skipped dry-run of Application/AppProject
# [OK] module 09 verified
```

`verify.sh`: при наличии `helm` делает `helm lint` + `helm template`; затем
dry-run валидирует Argo CD-манифесты, но **не падает** без установленных CRDs Argo
CD (мягкий `[WARN]`). Итог — `[OK] module 09 verified`.

---

## Финальная карта ресурсов модуля

| Ресурс | Что демонстрирует |
|--------|-------------------|
| `charts/demo-app` | Helm chart (templates + values) |
| `gitops/argocd/app.yaml` | Argo CD `Application` (repoURL/path/sync) |
| `gitops/argocd/project.yaml` | `AppProject` (границы безопасности) |
| `broken/scenario-01` | sync-фейл из-за неверного `path` |
| `solutions/01-argocd-path` | Решение первого инцидента |

---

## Теоретические вопросы (итоговые)

1. Обязательная структура Helm chart и роль элементов (`Chart.yaml`, `values.yaml`, `templates/`).
2. Как templating связывает `values.yaml` и манифесты? Что делают `toYaml`, `{{- if }}`, `{{- with }}`?
3. Приоритет values: что перебьёт что между `values.yaml`, `-f file`, `--set`? Зачем это нужно?
4. В чём суть GitOps и что такое drift? Как `selfHeal` и `prune` его устраняют?
5. Назовите 4 ключевых компонента Argo CD (repo-server, application-controller и др.) и роль каждого в sync-loop.
6. Чем **sync**-статус отличается от **health**-статуса? Приведите пример, когда может быть `Synced` + `Progressing` одновременно и почему это не ошибка.
7. Как `Application` и `AppProject` описывают и ограничивают деплой? Почему нельзя все деплоить в дефолтный `default` AppProject?
8. Какие существуют альтернативы хранению зашифрованных секретов (SOPS) в Git-репозитории?
9. Что произойдет, если мы удалим `Application` из кластера с ключом `--cascade=true` (по умолчанию)?

---

## Практические задания (отработка)

> Делайте на живом кластере; проверяйте себя командами и `verify/verify.sh`.

1. **Базовый Helm:** Переопределите values через `--set` и `-f`; покажите через `helm template`, что `--set` выигрывает.
2. **Откат релизов:** Установите Helm chart, затем обновите его с `--set replicaCount=3`. Сделайте откат (`helm rollback`) к первой ревизии и проверьте количество подов.
3. **Поломка Argo Application:** Сломайте `source.path` в Argo Application и прочитайте `ComparisonError` в `.status.conditions`.
4. **Проверка SelfHeal:** Проверьте selfHeal: удалите управляемый Deployment руками — Argo вернёт его; найдите событие восстановления в `kubectl get events -n lab`.
5. **Анализ дозревания ресурсов:** Доведите `demo-app` до `Healthy` (ingress-nginx есть) и сверьте по двум осям `sync`/`health`. Если у вас Ingress остается в `<pending>`, объясните, почему.
6. **Работа с CLI/YAML:** Через `kubectl -n argocd get app demo-app -o yaml` найдите раздел `.status.resources[]` и определите, какие именно ресурсы в данный момент отслеживает Argo CD.

---

## Шпаргалка

```bash
# === Helm ===
helm lint ./charts/demo-app
helm template demo-app ./charts/demo-app
helm upgrade --install demo-app ./charts/demo-app -n lab --create-namespace
helm upgrade --install demo-app ./charts/demo-app -n lab --set replicaCount=2
helm history demo-app -n lab
helm rollback demo-app 1 -n lab
helm uninstall demo-app -n lab

# === Argo CD ===
kubectl apply --dry-run=client -f gitops/argocd/app.yaml
# Проверить статус Sync и Health:
kubectl -n argocd get application demo-app -o jsonpath='sync={.status.sync.status} health={.status.health.status}{"\n"}'
# Посмотреть причины проблем:
kubectl -n argocd get application demo-app -o jsonpath='{.status.conditions}'

# === Уборка ===
helm uninstall demo-app -n lab 2>/dev/null
kubectl -n argocd delete application demo-app --ignore-not-found
```

---

## Чему вы научились

В этом расширенном модуле вы освоили:
- Создание, валидацию и упаковку приложений в Helm-чарты.
- Понимание жизненного цикла Helm релизов (install, upgrade, rollback).
- Декларативный деплой через Argo CD (GitOps) с глубоким пониманием архитектуры Push vs Pull.
- Разделение осей состояния на `Sync` (соответствие Git) и `Health` (реальное состояние в кластере).
- Системный troubleshooting типовых инцидентов деплоя.
- Безопасное управление секретами в парадигме GitOps.

## Уборка

```bash
# Подчистим за собой кластер
helm uninstall demo-app -n lab 2>/dev/null || true
kubectl -n argocd delete application demo-app --ignore-not-found 2>/dev/null || true
kubectl delete ns lab --ignore-not-found 2>/dev/null || true
```


## Решения (Solutions)
В данном модуле добавлены подробные решения для сломанных сценариев в папке `solutions/`. Пожалуйста, изучите их для лучшего понимания.
