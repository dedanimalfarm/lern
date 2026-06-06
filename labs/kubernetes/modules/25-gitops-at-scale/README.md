# Лабораторная работа 25: GitOps на масштабе (Kustomize overlays, ApplicationSet, multi-env)

## Оглавление
<!-- TOC -->
- [Предварительные требования](#-)
- [Стартовая проверка](#-)
- [Часть 1: Kustomize — base и overlays](#-1-kustomize--base--overlays)
  - [Теория для изучения перед частью](#----)
  - [1.1 Рендер overlays](#11--overlays)
- [Часть 2: ApplicationSet — один объект, много Application](#-2-applicationset-----application)
  - [Теория для изучения перед частью](#----)
  - [2.1 Применить ApplicationSet](#21--applicationset)
- [Часть 3: prune и selfHeal на масштабе](#-3-prune--selfheal--)
  - [Теория для изучения перед частью](#----)
  - [3.1 selfHeal: ручной дрейф откатывается](#31-selfheal---)
- [Часть 4: Другие паттерны масштабирования (обзор)](#-4----)
  - [Теория](#)
- [Часть 5: Troubleshooting — боевые инциденты](#-5-troubleshooting---)
  - [Теория: диагностика ApplicationSet/Application](#--applicationsetapplication)
  - [Инцидент 1: ApplicationSet породил битый Application (`path does not exist`)](#-1-applicationset---application-path-does-not-exist)
  - [Бонус: быстрая диагностика](#--)
- [Проверка модуля](#-)
- [Финальная карта ресурсов модуля](#---)
- [Теоретические вопросы (итоговые)](#--)
  - [Блок 1: Kustomize](#-1-kustomize)
  - [Блок 2: ApplicationSet](#-2-applicationset)
  - [Блок 3: GitOps на масштабе](#-3-gitops--)
- [Практические задания (отработка)](#--)
- [Шпаргалка](#)
- [Чему вы научились](#--)
- [Уборка](#)
<!-- /TOC -->


> ⏱ время ~30 мин · сложность 4/5 · пререквизиты: Трек 1 (Core)

Цель: научиться разворачивать ОДНО приложение в МНОГО окружений без копипасты —
через `Kustomize` (base + overlays на dev/staging/prod) и Argo CD `ApplicationSet`
(один объект порождает Application на каждое окружение). К концу модуля вы
понимаете разницу base/overlay, генераторы ApplicationSet, и как `prune`/`selfHeal`
держат N окружений в соответствии с git.

> Развитие модуля 09 (Helm + Argo CD Application — один деплой). Здесь — масштаб:
> много окружений из одного источника. Sync-waves/хуки (модуль 09, Часть 2)
> применимы и тут. Reconcile Application-контроллера — модель из модуля 01.

> ⚠️ **GitOps тянет из git, а не из вашей локальной папки.** Argo CD синхронизирует
> манифесты из `github.com/dedanimalfarm/lern.git` (ветка `main`). Любая правка
> overlay видна Argo только ПОСЛЕ `git push`. Эта лаба уже запушена — работает «из
> коробки»; свои изменения коммитьте, иначе Argo их не увидит.

---

## Предварительные требования

```bash
# kubeconfig нашего кластера (Kubespray); на другом стенде — свой путь/контекст
export KUBECONFIG=/root/.kube/kubespray.conf

# Argo CD уже установлен (ns argocd) вместе с ApplicationSet-контроллером:
kubectl -n argocd get deploy argocd-applicationset-controller
# argocd-applicationset-controller   1/1   ...

# kustomize встроен в kubectl (kubectl kustomize / kubectl apply -k)
kubectl version -o json | grep -m1 gitVersion   # v1.36.1
```

---

## Стартовая проверка

```bash
# Чисто ли (наших Application/namespaces ещё нет)
kubectl -n argocd get applicationset,applications | grep -E 'web-|web-environments' || echo "пусто — ок"
kubectl get ns | grep -E 'lab-(dev|staging|prod)' || echo "окружений ещё нет — ок"
```

Структура модуля (что лежит в git):

```
25-gitops-at-scale/
├── base/                    # общие Deployment + Service (один источник)
│   ├── deployment.yaml
│   ├── service.yaml
│   └── kustomization.yaml
├── overlays/                # точечные патчи на окружение
│   ├── dev/      (replicas 1, ns lab-dev)
│   ├── staging/  (replicas 2, ns lab-staging)
│   └── prod/     (replicas 3, ns lab-prod, пин образа)
└── applicationset/
    ├── appproject.yaml      # граница доверия (репо/namespaces)
    └── appset.yaml          # list-генератор -> 3 Application
```

---

## Часть 1: Kustomize — base и overlays

### Теория для изучения перед частью

- **Kustomize** собирает манифесты БЕЗ шаблонов (в отличие от Helm): есть `base`
  (общие ресурсы) и `overlays` (патчи поверх). `kubectl kustomize <dir>` рендерит,
  `kubectl apply -k <dir>` применяет.
- **overlay** ссылается на base через `resources: [../../base]` и накладывает
  изменения декларативно: `namespace:`, `replicas:`, `images:` (сменить тег),
  `patches:` (стратегический merge/JSON-patch), `labels:`/`configMapGenerator`.
- **Зачем:** dev/staging/prod отличаются немногим (число реплик, теги, лимиты,
  хосты) — держать три полные копии манифестов = дрейф и ошибки. Base+overlay =
  один источник правды + явная дельта на окружение.
- **Kustomize vs Helm:** Helm — шаблоны + values + релизы; Kustomize — наложение
  патчей без шаблонного языка. Argo CD умеет оба; часто комбинируют.

---

**Цель:** увидеть, как один base даёт три разных окружения.

**Ресурсы:** `base/`, `overlays/{dev,staging,prod}/`.

---

### 1.1 Рендер overlays

```bash
# Что именно меняет каждый overlay (без применения в кластер):
for e in dev staging prod; do
  echo "== $e =="
  kubectl kustomize overlays/$e | grep -E 'namespace:|replicas:|image:|env:'
done
# == dev ==      namespace: lab-dev      replicas: 1   image: nginx:1.27-alpine   env: dev
# == staging ==  namespace: lab-staging  replicas: 2                              env: staging
# == prod ==     namespace: lab-prod     replicas: 3   image: nginx:1.27.3-alpine env: prod
```

Видно: base один, дельта на окружение — только replicas, namespace, метка `env` и
(в prod) запиненный тег образа.

```bash
# Применить ОДНО окружение напрямую через kubectl (kustomize встроен), без Argo:
kubectl create ns lab-dev --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -k overlays/dev
kubectl -n lab-dev get deploy web      # 1/1
kubectl delete -k overlays/dev         # уборка ручного применения
```

**Контрольные вопросы:**
1. Чем base отличается от overlay?
2. Какие поля overlay переопределил у Deployment в prod?
3. Чем Kustomize отличается от Helm по способу кастомизации?

---

## Часть 2: ApplicationSet — один объект, много Application

### Теория для изучения перед частью

- **Проблема масштаба:** 3 окружения = 3 почти одинаковых Argo `Application`. 10
  окружений/кластеров — 10 копий, которые расходятся. **ApplicationSet** генерирует
  Application'ы по ШАБЛОНУ из **генератора**.
- **Генераторы** (откуда брать список):
  - `list` — явный список элементов (наш случай: dev/staging/prod);
  - `git` (directory) — Application на каждый каталог `overlays/*` в репо;
  - `cluster` — Application на каждый зарегистрированный кластер (multi-cluster);
  - `matrix`/`merge` — комбинация генераторов.
- **Шаблон** (`template`) — это Application с подстановками `{{.env}}` (при
  `goTemplate: true`). ApplicationSet-контроллер создаёт/обновляет/удаляет
  Application'ы при изменении генератора — добавил окружение в список, появился
  новый Application; убрал — удалился (с `prune` уедут и ресурсы).
- **AppProject** — граница доверия: из каких репо, в какие namespaces и какие
  ресурсы разрешено. `CreateNamespace=true` создаёт Namespace (cluster-scoped) —
  его надо разрешить в `clusterResourceWhitelist`.

---

**Цель:** одним ApplicationSet развернуть три окружения.

**Ресурсы:** `applicationset/appproject.yaml`, `applicationset/appset.yaml`.

---

### 2.1 Применить ApplicationSet

```bash
kubectl apply -f applicationset/appproject.yaml
kubectl apply -f applicationset/appset.yaml

# ApplicationSet сам породил три Application:
kubectl -n argocd get applicationset web-environments
kubectl -n argocd get applications
# NAME           SYNC STATUS   HEALTH STATUS
# web-dev        Synced        Healthy
# web-staging    Synced        Healthy
# web-prod       Synced        Healthy
```

```bash
# Каждое окружение развёрнуто в свой namespace с нужным числом реплик:
for e in dev staging prod; do kubectl -n lab-$e get deploy web; done
# lab-dev     web 1/1
# lab-staging web 2/2
# lab-prod    web 3/3   (образ nginx:1.27.3-alpine — пин из overlay)
```

> `web-<env>` — это обычные Argo Application'ы (их видно в UI), но управляет ими
> ApplicationSet: правка появляется через изменение генератора/шаблона, а не
> руками в каждом Application.

**Контрольные вопросы:**
1. Что произойдёт, если добавить `- env: qa` в list-генератор (и создать overlay)?
2. Зачем нужен AppProject и почему `Namespace` пришлось разрешать отдельно?
3. Чем `git`-генератор удобнее `list` для каталогов окружений?

---

## Часть 3: prune и selfHeal на масштабе

### Теория для изучения перед частью

- `syncPolicy.automated` включает непрерывную синхронизацию. **`selfHeal: true`** —
  откатывает РУЧНОЙ дрейф в кластере к состоянию git. **`prune: true`** — удаляет
  из кластера ресурсы, которых БОЛЬШЕ НЕТ в git.
- На масштабе это значит: «правда» одна — git; любое окружение, отклонившееся
  руками, возвращается; удалённое из набора — вычищается. Никаких «снежинок».
- **Порядок (sync-waves)** из модуля 09 (Часть 2) работает и здесь: внутри каждого
  Application ресурсы применяются по волнам (ns/CRD → конфиг → Deployment → Ingress).

---

**Цель:** убедиться, что git — единственный источник правды.

---

### 3.1 selfHeal: ручной дрейф откатывается

```bash
# Подкрутим прод вопреки git (overlay prod = 3 реплики):
kubectl -n lab-prod scale deploy web --replicas=7
sleep 20
kubectl -n lab-prod get deploy web
# web   3/3        <- Argo вернул к git: selfHeal отменил ручное изменение
```

```bash
# Видно в Application: был OutOfSync -> снова Synced
kubectl -n argocd get application web-prod \
  -o jsonpath='sync={.status.sync.status} health={.status.health.status}{"\n"}'
# sync=Synced health=Healthy
```

> `prune` демонстрируется правкой набора окружений в git (убрать env → Application
> и его ресурсы удаляются). В лабе это — `tasks/03-selfheal-prune.md`.

**Контрольные вопросы:**
1. Чем `selfHeal` отличается от `prune`?
2. Почему ручной `kubectl scale` в GitOps — антипаттерн?
3. Где в multi-env применяется порядок sync-waves?

---

## Часть 4: Другие паттерны масштабирования (обзор)

### Теория

- **App-of-Apps** — корневой Application, чей source — каталог с Application-
  манифестами. Проще ApplicationSet, но Application'ы пишутся руками (копипаста).
  ApplicationSet генерирует их из данных — предпочтительнее на масштабе.
- **git directory generator** — Application на каждый подкаталог `overlays/*`:
  добавил каталог окружения в репо → Application появился сам, без правки списка.
- **cluster generator** — Application на каждый кластер (multi-cluster GitOps:
  один ApplicationSet раскатывает app по всем prod-кластерам).
- **matrix generator** — декартово произведение (напр. {env} × {cluster}) для
  раскатки каждого окружения на каждый кластер.

```yaml
# Фрагмент: git directory generator вместо list (Application на каждый overlays/*)
generators:
  - git:
      repoURL: https://github.com/dedanimalfarm/lern.git
      revision: main
      directories:
        - path: labs/kubernetes/modules/25-gitops-at-scale/overlays/*
```

**Контрольные вопросы:**
1. Чем ApplicationSet лучше App-of-Apps?
2. Когда нужен `matrix`-генератор?

---

## Часть 5: Troubleshooting — боевые инциденты

### Теория: диагностика ApplicationSet/Application

```
Окружение не разворачивается
│
├─ Application НЕ создан ───────► describe applicationset web-environments → Events:
│     генератор пуст? ошибка шаблона ({{.field}} опечатка при missingkey=error)?
├─ Application есть, Unknown/ComparisonError ► path/repoURL неверны (Сценарий 01):
│     get application <app> -o jsonpath status.conditions → "app path does not exist"
├─ OutOfSync, не синхронизируется ► AppProject запрещает namespace/ресурс/репо:
│     describe application → "project ... is not permitted"; правь appproject
├─ Synced, но Degraded/Missing ─► сам ресурс в ошибке (CrashLoop/образ) — смотри под
└─ Namespace не создан ─────────► CreateNamespace=true есть? Namespace в
      clusterResourceWhitelist проекта?
```

---

### Инцидент 1: ApplicationSet породил битый Application (`path does not exist`)

Оформлен как `broken/scenario-01/` — опечатка в элементе генератора (`stagng`)
рождает Application `web-stagng` с несуществующим path. Полный цикл (симптом →
диагностика → решение) — в `broken/scenario-01/README.md`.

```bash
kubectl apply -f broken/scenario-01/appset-broken.yaml
sleep 10
kubectl -n argocd get applications        # web-stagng в SYNC=Unknown (path не найден)
kubectl -n argocd get application web-stagng -o jsonpath='{.status.conditions[*].message}{"\n"}'
# ... overlays/stagng: app path does not exist

# Решение: исправить опечатку (stagng -> staging), переприменить.
kubectl apply -f solutions/01-path/appset-fixed.yaml
# ApplicationSet удалит web-stagng и создаст web-staging.
```

### Бонус: быстрая диагностика

```bash
# Все Application и их статусы
kubectl -n argocd get applications -o wide
# Почему Application не синхронизируется (conditions)
kubectl -n argocd get application <app> -o jsonpath='{range .status.conditions[*]}{.type}: {.message}{"\n"}{end}'
# Что нагенерил ApplicationSet (и есть ли ошибки генератора/шаблона)
kubectl -n argocd describe applicationset web-environments | tail -20
```

---

## Проверка модуля

```bash
# Развернуть (если ещё не сделано в Части 2):
kubectl apply -f applicationset/appproject.yaml
kubectl apply -f applicationset/appset.yaml

# Автопроверка (ждёт Synced/Healthy и проверяет реплики по окружениям)
bash verify/verify.sh
# [OK] applicationset/web-environments present
# [OK] appproject/labs-gitops present
# [OK] web-dev Synced/Healthy, deploy web in lab-dev has 1 replica(s)
# [OK] web-staging Synced/Healthy, deploy web in lab-staging has 2 replica(s)
# [OK] web-prod Synced/Healthy, deploy web in lab-prod has 3 replica(s)
# [OK] module 25 verified
```

---

## Финальная карта ресурсов модуля

| Ресурс | Тип | Роль |
|--------|-----|------|
| `web-environments` | ApplicationSet (ns argocd) | list-генератор → 3 Application |
| `labs-gitops` | AppProject (ns argocd) | граница доверия (репо/lab-*/ресурсы) |
| `web-dev/staging/prod` | Application (ns argocd) | синхронизируют свои overlays |
| `web` | Deployment+Service ×3 | в lab-dev (1), lab-staging (2), lab-prod (3) |
| `base/` + `overlays/*` | Kustomize | один источник + дельты окружений |

---

## Теоретические вопросы (итоговые)

### Блок 1: Kustomize
1. base vs overlay — кто на кого ссылается?
2. Какими трансформерами overlay меняет реплики и тег образа?
3. Kustomize vs Helm — в чём разница подхода?

### Блок 2: ApplicationSet
4. Что делает list-генератор и чем его заменить для каталогов (git-генератор)?
5. Что произойдёт при добавлении/удалении элемента генератора?
6. Зачем AppProject и почему Namespace в clusterResourceWhitelist?

### Блок 3: GitOps на масштабе
7. selfHeal vs prune — что каждый делает?
8. Почему ручной `kubectl edit` окружения — антипаттерн в GitOps?
9. App-of-Apps vs ApplicationSet — когда что?

---

## Практические задания (отработка)

См. подробные сценарии в `tasks/`:

1. **`tasks/01-kustomize-overlays.md`** — рендер overlays, сравнение дельт, `apply -k`.
2. **`tasks/02-applicationset.md`** — ApplicationSet → 3 Application; добавить env=qa.
3. **`tasks/03-selfheal-prune.md`** — drift откатывается (selfHeal), удаление из
   набора вычищает окружение (prune).

Дополнительно:
4. Замените list-генератор на `git` directory generator (Application на каждый
   `overlays/*`) и убедитесь, что результат тот же.
5. Добавьте в prod-overlay `patches` с увеличенными `resources.limits` и проверьте,
   что dev/staging не затронуты.

---

## Шпаргалка

```bash
# === Kustomize ===
kubectl kustomize overlays/<env>          # отрендерить
kubectl apply -k overlays/<env>           # применить напрямую (без Argo)

# === ApplicationSet / Application ===
kubectl apply -f applicationset/appproject.yaml -f applicationset/appset.yaml
kubectl -n argocd get applicationset,applications
kubectl -n argocd get application <app> -o jsonpath='{.status.sync.status}/{.status.health.status}{"\n"}'

# === Диагностика ===
kubectl -n argocd describe applicationset web-environments | tail -20
kubectl -n argocd get application <app> -o jsonpath='{range .status.conditions[*]}{.type}: {.message}{"\n"}{end}'

# === Уборка модуля ===
kubectl -n argocd delete applicationset web-environments   # удалит и все web-* Application (+prune ресурсов)
kubectl -n argocd delete appproject labs-gitops
kubectl delete ns lab-dev lab-staging lab-prod --ignore-not-found
```

---


## Чему вы научились

В этом модуле вы научились:
- Управлению множеством окружений (multi-env) через Kustomize
- Массовому деплою с помощью Argo CD ApplicationSet
- Структурированию репозитория для GitOps

## Уборка

```bash
# Удаление ApplicationSet каскадно удаляет порождённые Application, а prune —
# их ресурсы в кластере:
kubectl -n argocd delete applicationset web-environments --ignore-not-found
kubectl -n argocd delete appproject labs-gitops --ignore-not-found
kubectl delete ns lab-dev lab-staging lab-prod --ignore-not-found
```

> Дальше по ROADMAP: **progressive-delivery** (Argo Rollouts: canary/blue-green с
> анализом метрик) — следующий слой над GitOps-доставкой.
