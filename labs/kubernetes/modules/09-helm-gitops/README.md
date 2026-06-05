# Лабораторная работа 09: Helm и GitOps (Argo CD)

> ⏱ время ~25 мин · сложность 2/5 · пререквизиты: Трек 1 (Core)

Цель: упаковать приложение в Helm chart и разворачивать его декларативно через
GitOps (Argo CD) — где Git является источником истины, а контроллер постоянно
выравнивает состояние кластера под репозиторий. К концу модуля вы рендерите
chart, ставите release и читаете причину sync-фейла.

---

## Предварительные требования

```bash
# kubeconfig нашего кластера (Kubespray); на другом стенде — свой путь/контекст
export KUBECONFIG=/root/.kube/kubespray.conf
# helm нужен для Части 1
helm version --short 2>/dev/null || echo "helm не установлен — поставьте для Части 1"

## Стартовая проверка

Убедитесь, что кластер доступен:
```bash
kubectl get nodes
```

# Argo CD (Часть 2) опционален: манифесты можно проверить dry-run и без него,
# но для РЕАЛЬНОГО sync нужен установленный Argo CD. Ставьте пиннутым скриптом
# (он использует --server-side, иначе большой CRD applicationsets не применится):
#   bash ../../scripts/bootstrap/06-install-argocd.sh
kubectl get ns argocd 2>/dev/null || echo "argocd не установлен — dry-run манифестов всё равно сработает"
```

---

## Часть 1: Helm chart

### Теория для изучения перед частью

- **Chart** — параметризованный пакет манифестов: `Chart.yaml` (метаданные),
  `values.yaml` (параметры), `templates/` (Go-template, рендерятся в YAML).
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

> Для крупных chart'ов повторяющиеся куски (labels, имена) выносят в именованные
> шаблоны `_helpers.tpl` и подключают через `{{ include "name" . }}`. В этом
> минимальном demo их НЕТ — labels продублированы прямо в шаблонах (так нагляднее).

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

```bash
helm lint ./charts/demo-app
# 1 chart(s) linted, 0 chart(s) failed

helm template demo-app ./charts/demo-app | grep -E "kind:|image:|host:"
# kind: ConfigMap / Deployment / Service / Ingress
# image: "nginx:1.27-alpine"
# host: demo-app.local
```

### 1.2 Установка release

```bash
helm upgrade --install demo-app ./charts/demo-app -n lab --create-namespace
kubectl -n lab get deploy,svc,ingress -l app.kubernetes.io/name=demo-app
```

### 1.3 Переопределение values

```bash
helm upgrade --install demo-app ./charts/demo-app -n lab \
  --set replicaCount=2 --set image.tag=1.27.5-alpine
kubectl -n lab get deploy demo-app -o jsonpath='{.spec.replicas}{"\n"}'   # 2
```

**Контрольные вопросы:**
1. Из каких обязательных частей состоит Helm chart?
2. Как `values.yaml` и `templates/` дают итоговый манифест?
3. Чем полезны `helm lint`/`helm template` до деплоя?
4. Почему `helm upgrade --install` идемпотентен?

---

## Часть 2: GitOps и Argo CD

### Теория для изучения перед частью

- **GitOps:** желаемое состояние в Git, контроллер (Argo CD/Flux) непрерывно
  сравнивает его с кластером и устраняет **drift** (ручные правки откатываются к
  Git). Деплой = коммит.
- **Argo CD `Application`** описывает ЧТО синхронизировать (`repoURL`, `path`,
  `targetRevision`, namespace) и КАК (`syncPolicy`: `automated`/`prune`/
  `selfHeal`). **`AppProject`** задаёт границы (репозитории, namespaces, ресурсы).

**Архитектура Argo CD (что реально стоит в ns `argocd`, v3.4.3 — 7 компонентов):**

```
            Git (source of truth)
               │  репо + path + targetRevision
               ▼
   ┌──────────── ns argocd ─────────────────────────────────────────┐
   │  repo-server          → клонирует Git, РЕНДЕРИТ манифесты        │
   │                         (helm template / kustomize build)       │
   │  application-controller→ сравнивает desired(Git) ↔ live(кластер),│ ──┐
   │                         считает sync/health, делает apply        │   │ kube-apiserver
   │  redis                → кэш отрендеренного/diff                   │   ▼
   │  server (API/UI)  dex(SSO)  applicationset  notifications        │  ns lab (Deployment/Svc/…)
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
> «дозрел» до Healthy). См. 2.2.

#### Sync-waves и хуки Argo CD: порядок применения ресурсов

По умолчанию Argo CD применяет все ресурсы разом, но сложный деплой требует
ПОРЯДКА: CRD → namespace/ConfigMap → Deployment → миграция → Ingress. Порядок
задаёт аннотация `argocd.argoproj.io/sync-wave` (целое; меньше = раньше):

```
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
  к следующей — поэтому в волну ставят Job-миграцию перед Deployment приложения.
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

**selfHeal вживую (откат drift):**

```bash
# Удаляем управляемый ресурс «руками» — Argo CD вернёт его (selfHeal: true)
kubectl -n lab delete deploy demo-app
# через ~10-20с deployment снова есть и Ready=1/1 — контроллер устранил drift:
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

**Контрольные вопросы:**
1. Что является source of truth в GitOps и как идёт деплой?
2. Что такое drift и как `selfHeal` его устраняет?
3. Роли `Application` и `AppProject`?
4. Что делает `prune: true`?

---

## Часть 3: Troubleshooting

### Системная методология (по двум осям статуса)

Не угадывать, а читать sync и health — они указывают РАЗНЫЕ классы проблем:

```
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

### Инцидент 1: Argo CD не синхронизирует — неверный `path`

Оформлен в `broken/scenario-01/`: `spec.source.path` указывает на несуществующий
`charts/wrong-path`.

**Диагностика (при установленном Argo CD):**

```bash
kubectl apply -f broken/scenario-01/app.yaml
kubectl -n argocd get application demo-app
# SYNC STATUS: Unknown   HEALTH: Missing      <- манифесты не найдены
kubectl -n argocd get application demo-app -o jsonpath='{.status.conditions}'
# ... "ComparisonError" ... path '.../charts/wrong-path' does not exist
```

**Решение:**

```bash
kubectl apply -f solutions/01-argocd-path/app.yaml   # path -> .../charts/demo-app
```

**Профилактика:** `path`/`repoURL` в `Application` — контракт со структурой
репозитория; проверять при каждом reorg (этот модуль и чинил устаревшие
`glebbykov`/`k8s-new/k8s-labs` → `dedanimalfarm`/`labs/kubernetes`).

**Контрольные вопросы:**
1. Как Argo CD сообщает, что не нашёл манифесты по `path`?
2. Почему `repoURL`/`path` нужно держать в синхроне со структурой репо?

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
| `gitops/argocd/project.yaml` | `AppProject` (границы) |
| `broken/scenario-01` | sync-фейл из-за неверного `path` |

---

## Теоретические вопросы (итоговые)

1. Обязательная структура Helm chart и роль элементов.
2. Как templating связывает `values.yaml` и манифесты? Что делают `toYaml`,
   `{{- if }}`, `{{- with }}`?
3. Приоритет values: что перебьёт что между `values.yaml`, `-f file`, `--set`?
4. В чём суть GitOps и что такое drift? Как `selfHeal` и `prune` его устраняют?
5. Назовите 4 компонента Argo CD и роль каждого в sync-loop.
6. Чем **sync**-статус отличается от **health**-статуса? Может ли быть
   `Synced` + `Progressing` одновременно и почему это не ошибка?
7. Как `Application`/`AppProject` описывают и ограничивают деплой?
8. Три типовые причины sync-фейла и как их различить по `sync`/`health`.

---

## Практические задания (отработка)

> Делайте на живом кластере; проверяйте себя командами и `verify/verify.sh`.

1. Переопределите values через `--set` и `-f`; покажите, что `--set` выигрывает.
2. Сломайте `source.path` в Argo Application и прочитайте `ComparisonError` в `.status.conditions`.
3. Проверьте selfHeal: удалите управляемый Deployment руками — Argo вернёт его; найдите событие.
4. Доведите `demo-app` до `Healthy` (ingress-nginx есть) и сверьте по двум осям `sync`/`health`.
5. Через `kubectl -n argocd ... -o yaml` найдите `.status.resources[]` и определите «недозревший» ресурс.

---

## Шпаргалка

```bash
# === Helm ===
helm lint ./charts/demo-app
helm template demo-app ./charts/demo-app
helm upgrade --install demo-app ./charts/demo-app -n lab --create-namespace
helm uninstall demo-app -n lab

# === Argo CD ===
kubectl apply --dry-run=client -f gitops/argocd/app.yaml
kubectl -n argocd get application demo-app -o jsonpath='{.status.conditions}'

# === Уборка ===
helm uninstall demo-app -n lab 2>/dev/null
kubectl -n argocd delete application demo-app --ignore-not-found
```

---

## Уборка

```bash
helm uninstall demo-app -n lab 2>/dev/null || true
kubectl -n argocd delete application demo-app --ignore-not-found 2>/dev/null || true
```
