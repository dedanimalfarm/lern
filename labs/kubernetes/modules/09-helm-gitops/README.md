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
2. Как templating связывает `values.yaml` и манифесты?
3. В чём суть GitOps и что такое drift?
4. Как `Application`/`AppProject` описывают и ограничивают деплой?
5. Три типовые причины sync-фейла в Argo CD.

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
