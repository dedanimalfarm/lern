# Лабораторная работа 09: Helm и GitOps (Argo CD)

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
# sync=Synced health=Progressing rev=4d8c64b...   <- Synced = состояние совпало с Git
```

> ✅ **Прогнано на нашем Kubespray-кластере (Argo CD v3.4.3):** Application `demo-app`
> → **Synced** с ревизии `main`; в ns `lab` появились Deployment/Service/ConfigMap/Ingress
> прямо из Git. Приложение реально отвечает: `wget -qO- http://demo-app/` →
> `<title>Welcome to nginx!</title>`.

**selfHeal вживую (откат drift):**

```bash
# Удаляем управляемый ресурс «руками» — Argo CD вернёт его (selfHeal: true)
kubectl -n lab delete deploy demo-app
# через ~10-20с deployment снова есть и Ready=1/1 — контроллер устранил drift:
kubectl -n lab get deploy demo-app
```

> **health=Progressing — это НЕ сбой GitOps.** Так помечен Ingress `demo-app`
> (`ingress.enabled: true` в chart): Argo CD считает Ingress Healthy только когда у
> него есть `status.loadBalancer.ingress` (адрес), а на кластере нет
> ingress-controller (см. модуль 04, Часть 3) — адрес не выдаётся, поэтому
> Progressing. Сам workload Healthy, sync=Synced. Чтобы довести до Healthy —
> поставьте ingress-controller или `helm.parameters: ingress.enabled=false` в
> Application. `prune: true` удалит из кластера то, что убрали из Git (полный GitOps).

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
