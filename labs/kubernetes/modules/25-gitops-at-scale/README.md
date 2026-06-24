# Лабораторная работа 25: GitOps на масштабе (Kustomize overlays, ApplicationSet, multi-env)

## Оглавление
<!-- TOC -->
- [Предварительные требования](#предварительные-требования)
- [Стартовая проверка](#стартовая-проверка)
- [Архитектурный обзор: GitOps на масштабе](#архитектурный-обзор-gitops-на-масштабе)
  - [Почему мы отказываемся от Helm templates в пользу Kustomize?](#почему-мы-отказываемся-от-helm-templates-в-пользу-kustomize)
  - [Место ApplicationSet в экосистеме Argo CD](#место-applicationset-в-экосистеме-argo-cd)
- [Часть 1: Kustomize — base и overlays](#часть-1-kustomize--base-и-overlays)
  - [Теория: Анатомия Kustomize](#теория-анатомия-kustomize)
  - [1.1 Рендер overlays: смотрим под капот](#11-рендер-overlays-смотрим-под-капот)
  - [1.2 Ручное применение overlay (без Argo CD)](#12-ручное-применение-overlay-без-argo-cd)
  - [1.3 Создание нового overlay с нуля (QA окружение)](#13-создание-нового-overlay-с-нуля-qa-окружение)
- [Часть 2: ApplicationSet — один объект, много Application](#часть-2-applicationset--один-объект-много-application)
  - [Теория: Как работает ApplicationSet Controller](#теория-как-работает-applicationset-controller)
  - [2.1 Применить ApplicationSet (List Generator)](#21-применить-applicationset-list-generator)
  - [2.2 Альтернатива: ApplicationSet с Git Generator](#22-альтернатива-applicationset-с-git-generator)
  - [2.3 Безопасность и изоляция через AppProject](#23-безопасность-и-изоляция-через-appproject)
- [Часть 3: prune и selfHeal на масштабе](#часть-3-prune-и-selfheal-на-масштабе)
  - [Теория: Жизненный цикл синхронизации в Argo CD](#теория-жизненный-цикл-синхронизации-в-argo-cd)
  - [3.1 selfHeal: ручной дрейф откатывается](#31-selfheal-ручной-дрейф-откатывается)
  - [3.2 prune: каскадное удаление окружения через Git](#32-prune-каскадное-удаление-окружения-через-git)
- [Часть 4: Другие паттерны масштабирования (обзор)](#часть-4-другие-паттерны-масштабирования-обзор)
  - [App-of-Apps vs ApplicationSet](#app-of-apps-vs-applicationset)
  - [Matrix Generator: декартово произведение для Multi-Cluster](#matrix-generator-декартово-произведение-для-multi-cluster)
- [Часть 5: Troubleshooting — боевые инциденты на проде](#часть-5-troubleshooting--боевые-инциденты-на-проде)
  - [Теория: Алгоритм диагностики ApplicationSet/Application](#теория-алгоритм-диагностики-applicationsetapplication)
  - [Инцидент 1: ApplicationSet породил битый Application (`path does not exist`)](#инцидент-1-applicationset-породил-битый-application-path-does-not-exist)
  - [Инцидент 2: AppProject запрещает развертывание (Permissions Denied)](#инцидент-2-appproject-запрещает-развертывание-permissions-denied)
  - [Инцидент 3: Бесконечный цикл синхронизации (Flapping / OutOfSync) из-за Mutating Webhook](#инцидент-3-бесконечный-цикл-синхронизации-flapping--outofsync-из-за-mutating-webhook)
  - [Инцидент 4: Конфликт имён (Collision) при генерации Application](#инцидент-4-конфликт-имён-collision-при-генерации-application)
  - [Бонус: быстрая CLI диагностика](#бонус-быстрая-cli-диагностика)
- [Проверка модуля](#проверка-модуля)
- [Финальная карта ресурсов модуля](#финальная-карта-ресурсов-модуля)
- [Теоретические вопросы (итоговые)](#теоретические-вопросы-итоговые)
  - [Блок 1: Kustomize](#блок-1-kustomize)
  - [Блок 2: ApplicationSet](#блок-2-applicationset)
  - [Блок 3: GitOps на масштабе](#блок-3-gitops-на-масштабе)
- [Практические задания (отработка)](#практические-задания-отработка)
- [Шпаргалка](#шпаргалка)
- [Чему вы научились](#чему-вы-научились)
- [Уборка](#уборка)
<!-- /TOC -->

> ⏱ время ~60-90 мин · сложность 4/5 · пререквизиты: Трек 1 (Core), Helm, Argo CD базовый уровень

Цель: научиться разворачивать ОДНО приложение в МНОГО окружений без копипасты — через `Kustomize` (base + overlays на dev/staging/prod/qa) и Argo CD `ApplicationSet` (один объект порождает множество Application на каждое окружение или кластер). К концу модуля вы будете глубоко понимать разницу base/overlay, возможности генераторов ApplicationSet (List, Git, Matrix), алгоритмы синхронизации `prune`/`selfHeal`, а также научитесь диагностировать сложные сбои на масштабе (отсутствие путей, нехватка прав в AppProject, бесконечные циклы синхронизации).

> Развитие модуля 09 (Helm + Argo CD Application — один деплой). Здесь — масштаб: много окружений из одного источника. Концепции Sync-waves и хуков применимы и тут. Reconcile Application-контроллера — модель из модуля 01, возведённая в степень.

> ⚠️ **GitOps тянет из git, а не из вашей локальной папки.** Argo CD синхронизирует манифесты из вашего git-репозитория. Любая правка overlay или ApplicationSet видна Argo только ПОСЛЕ `git push`. Эта лаба спроектирована так, чтобы базовый сценарий работал «из коробки», но для выполнения дополнительных заданий свои изменения обязательно нужно коммитить и пушить.

---

## Предварительные требования

Перед началом работы убедитесь, что ваш кластер готов к GitOps-нагрузкам. Нам потребуется рабочий Kubernetes кластер, установленный Argo CD и плагины Kustomize.

```bash
# Убедитесь, что вы подключены к правильному кластеру
export KUBECONFIG=/root/.kube/kubespray.conf

# Проверяем доступность API-сервера
kubectl cluster-info

# В Argo CD версии 2.0+ ApplicationSet контроллер поставляется "из коробки" 
# (раньше его приходилось ставить отдельно). Убедимся, что он запущен и готов:
kubectl -n argocd get deploy argocd-applicationset-controller
# Ожидаемый вывод:
# NAME                               READY   UP-TO-DATE   AVAILABLE   AGE
# argocd-applicationset-controller   1/1     1            1           5d

# Проверим сам Argo CD server и repo-server (именно он отвечает за рендер манифестов)
kubectl -n argocd get pods -l app.kubernetes.io/name=argocd-repo-server

# kustomize встроен в kubectl (через подкоманду kustomize или флаг -k),
# но иногда полезно иметь standalone kustomize CLI для advanced-фич.
# Проверим версию кластера (сервера); grep -m1 дал бы версию КЛИЕНТА kubectl:
kubectl version -o json | grep -A3 '"serverVersion"' | grep gitVersion   # сервер: желательно v1.36.1+
```

**Почему `argocd-repo-server` так важен?** 
Именно этот компонент клонирует ваш Git-репозиторий, кэширует его, запускает нужную команду генерации (например, `kustomize build` или `helm template`) и возвращает сырой YAML обратно в `argocd-application-controller`, который уже сравнивает этот YAML с текущим ("Live") состоянием кластера. 

---

## Стартовая проверка

Убедимся, что кластер чист и готов к лабораторной работе. Наличие старых Application от прошлых лабораторных может вызвать конфликты имён или попытки развернуть ресурсы в те же неймспейсы.

```bash
# Проверяем, нет ли "остатков" прошлых запусков: наших Application и ApplicationSet
kubectl -n argocd get applicationset,applications | grep -E 'web-|web-environments' || echo "пусто — ок"

# Проверяем наличие целевых неймспейсов (их не должно быть)
kubectl get ns | grep -E 'lab-(dev|staging|prod)' || echo "окружений ещё нет — ок"
```

Структура каталогов нашего модуля (что лежит в git):

```text
25-gitops-at-scale/
├── base/                    # Общие ресурсы: Deployment, Service (Единый источник правды)
│   ├── deployment.yaml      # Базовый деплоймент (образ, порты, селекторы)
│   ├── service.yaml         # Базовый сервис (ClusterIP)
│   └── kustomization.yaml   # Указывает, что объединять в base
├── overlays/                # Точечные патчи на каждое окружение
│   ├── dev/                 # Окружение разработчиков (replicas 1, ns lab-dev)
│   │   ├── kustomization.yaml
│   │   └── patch-replicas.yaml
│   ├── staging/             # Предпродовое окружение (replicas 2, ns lab-staging)
│   └── prod/                # Продакшен (replicas 3, ns lab-prod, фиксация версии образа)
└── applicationset/
    ├── appproject.yaml      # AppProject: Граница доверия и секурити-политики
    └── appset.yaml          # ApplicationSet: list-генератор -> 3 Application
```

---

## Архитектурный обзор: GitOps на масштабе

В этом модуле мы соединяем две мощные технологии: Kustomize (для управления конфигурациями без шаблонизации) и Argo CD ApplicationSet (для автоматизации создания контроллеров развертывания). 

### Почему мы отказываемся от Helm templates в пользу Kustomize?

Исторически многие команды использовали Helm для управления конфигурацией между окружениями. Они создавали `values.yaml`, `values-dev.yaml`, `values-prod.yaml` и вставляли `{{ if eq .Values.env "prod" }}` по всем шаблонам. Со временем это приводило к тому, что Helm-чарты становились нечитаемыми из-за обилия логики. 

Kustomize предлагает принципиально иной подход — *template-free customization*. У вас есть полностью рабочий чистый YAML в папке `base`. В папке `overlays` вы кладете только *патчи* — инструкции о том, как изменить базовый YAML. Kustomize применяет эти патчи на лету (используя стратегию Strategic Merge Patch).

### Место ApplicationSet в экосистеме Argo CD

Если Kustomize решает проблему "как сгенерировать YAML для 100 окружений без дублирования", то ApplicationSet решает проблему "как заставить Argo CD управлять этими 100 окружениями, не создавая 100 ручных объектов `Application`". 

Вот как это выглядит архитектурно:

```mermaid
graph TD
    %% Kustomize Layer
    subgraph "Слой рендеринга манифестов (Kustomize)"
        B[base/ <br> Deployment, Service] --> O1[overlays/dev]
        B --> O2[overlays/staging]
        B --> O3[overlays/prod]
        
        O1 -- kustomize build --> YAML_DEV[Сырой YAML (Dev)]
        O2 -- kustomize build --> YAML_STG[Сырой YAML (Staging)]
        O3 -- kustomize build --> YAML_PROD[Сырой YAML (Prod)]
    end

    %% Argo CD Layer
    subgraph "Слой оркестрации GitOps (Argo CD)"
        AS[ApplicationSet <br> 'web-environments']
        G[List Generator <br> dev, staging, prod] --> AS
        
        AS -- Template rendering --> APP1[Application 'web-dev']
        AS -- Template rendering --> APP2[Application 'web-staging']
        AS -- Template rendering --> APP3[Application 'web-prod']
    end

    %% Cluster Layer
    subgraph "Слой кластера (Kubernetes)"
        APP1 --> |Sync| NS1((Namespace: lab-dev))
        APP2 --> |Sync| NS2((Namespace: lab-staging))
        APP3 --> |Sync| NS3((Namespace: lab-prod))
    end
    
    YAML_DEV -. Live Diff .-> APP1
    YAML_STG -. Live Diff .-> APP2
    YAML_PROD -. Live Diff .-> APP3
```

**Ключевые принципы архитектуры:**
1. **DRY (Don't Repeat Yourself)**: Базовые манифесты лежат в одном месте (`base/`). Окружения содержат только отличия (дельты).
2. **Бесшовная автоматизация**: При добавлении нового окружения вам не нужно писать новый `Application`. Вы просто добавляете папку `overlays/new-env` и обновляете генератор в `ApplicationSet`.
3. **Безопасность (Boundary)**: `AppProject` жестко ограничивает, какие кластеры, неймспейсы и типы ресурсов могут быть развернуты, снижая радиус поражения при взломе или ошибке.

---

## Часть 1: Kustomize — base и overlays

### Теория: Анатомия Kustomize

- **Kustomize** работает исключительно на уровне структуры YAML. 
- **kustomization.yaml** — главный файл Kustomize. Он может включать:
  - `resources`: ссылки на файлы или папки (например, `../../base`), которые нужно включить в сборку.
  - `namespace`: переопределение неймспейса для всех ресурсов (Deployment, Service, ConfigMap и т.д.).
  - `namePrefix` / `nameSuffix`: добавление префиксов/суффиксов ко всем именам (автоматически обновляет селекторы!).
  - `commonLabels` / `commonAnnotations`: добавление меток ко всем объектам и их селекторам.
  - `images`: подмена тегов или репозиториев (например, `nginx:latest` -> `nginx:1.27.3-alpine`).
  - `patches` (или `patchesStrategicMerge` / `patchesJson6902`): наложение изменений. Вы можете изменить количество реплик, добавить переменную окружения, примонтировать volume.

### 1.1 Рендер overlays: смотрим под капот

Давайте посмотрим, как `kustomize` объединяет base и overlays на лету. Мы просто выводим результат в терминал (рендеринг), не применяя его в кластер.

```bash
# Посмотрим, что именно меняет каждый overlay:
for e in dev staging prod; do
  echo -e "\n----------------------------------------"
  echo -e "== Рендер окружения: $e =="
  echo -e "----------------------------------------"
  # Мы фильтруем вывод, чтобы показать только самые важные измененные поля
  kubectl kustomize overlays/$e | grep -E 'namespace:|replicas:|image:|env:'
done

# Ожидаемый вывод:
# ----------------------------------------
# == Рендер окружения: dev ==
# ----------------------------------------
#       env: dev
#       image: nginx:1.27-alpine
#   namespace: lab-dev
#   replicas: 1
# 
# ----------------------------------------
# == Рендер окружения: staging ==
# ----------------------------------------
#       env: staging
#       image: nginx:1.27-alpine
#   namespace: lab-staging
#   replicas: 2
# 
# ----------------------------------------
# == Рендер окружения: prod ==
# ----------------------------------------
#       env: prod
#       image: nginx:1.27.3-alpine
#   namespace: lab-prod
#   replicas: 3
```

Видно: каталог `base` один, но мы получаем три совершенно разных манифеста. Дельта на окружение — только replicas, namespace, метка `env` и (в prod) жестко запиненный тег образа для надежности продакшена.

### 1.2 Ручное применение overlay (без Argo CD)

Вы можете применить одно окружение напрямую через kubectl (kustomize встроен в него), без использования Argo CD. Это часто используется при отладке.

```bash
# dry-run=client создает YAML для неймспейса, который мы пайпим в kubectl apply
kubectl create ns lab-dev --dry-run=client -o yaml | kubectl apply -f -

# -k указывает kubectl использовать kustomize для директории
kubectl apply -k overlays/dev

# Проверяем результат (должен быть 1 под):
kubectl -n lab-dev get deploy web      
# NAME   READY   UP-TO-DATE   AVAILABLE   AGE
# web    1/1     1            1           10s

# Уборка ручного применения, так как дальше мы доверим это Argo CD
kubectl delete -k overlays/dev         
kubectl delete ns lab-dev
```

### 1.3 Создание нового overlay с нуля (QA окружение)

Попробуем самостоятельно понять, как создать конфигурацию для QA-окружения, используя существующий `base`. (Этот шаг чисто локальный, для понимания механики).

```bash
# 1. Создаем директорию для overlay
mkdir -p overlays/qa

# 2. Создаем файл kustomization.yaml
cat << 'EOF' > overlays/qa/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Наследуем манифесты из base
resources:
  - ../../base

# Задаем свой namespace
namespace: lab-qa

# Добавляем специфичный лейбл для всех ресурсов
commonLabels:
  env: qa

# Патчим образ (указываем конкретный тег, который сейчас тестируют QA)
images:
  - name: nginx
    newTag: "1.26-alpine"

# Применяем патч для реплик
patches:
  - path: patch-replicas.yaml
EOF

# 3. Создаем YAML с патчем реплик. Kustomize найдет Deployment 'web' 
# и применит к нему эту дельту.
cat << 'EOF' > overlays/qa/patch-replicas.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 4
EOF

# 4. Проверяем рендер QA
kubectl kustomize overlays/qa | grep -E 'namespace:|replicas:|image:|env:'
```

Вы увидите, как Kustomize подхватил `replicas: 4`, тег `1.26-alpine` и проставил лейблы. Это магия декларативного патчинга! Уберите директорию `qa`, чтобы не засорять репозиторий: `rm -rf overlays/qa`.

---

## Часть 2: ApplicationSet — один объект, много Application

### Теория: Как работает ApplicationSet Controller

- **Проблема масштаба:** Допустим, 3 окружения = 3 почти одинаковых объекта Argo `Application`. А если у нас 50 микросервисов в 4 окружениях, раскиданных по 3 региональным кластерам? Это 600 `Application` YAML-файлов. Держать их в актуальном состоянии вручную — это копипаста, дрейф конфигураций и ад поддержки.
- **Решение: ApplicationSet контроллер**. Это отдельный контроллер в экосистеме Argo, который генерирует Argo `Application`'ы по ШАБЛОНУ, получая переменные из **генератора**.
- **Генераторы** (источники данных, "откуда брать список"):
  - `List generator` — явный JSON/YAML список элементов (наш текущий случай: dev/staging/prod). Самый простой вариант, подходит для малых проектов.
  - `Git generator (directory/files)` — генерирует параметры на основе файлов/директорий в Git репозитории. Например: "создай Application на каждый каталог `overlays/*` в репо". Очень мощный паттерн — вы просто пушите новую папку в Git, и ArgoCD сам разворачивает окружение!
  - `Cluster generator` — опрашивает секреты кластеров, подключенных к ArgoCD (в неймспейсе argocd хранятся секреты с лейблом `argocd.argoproj.io/secret-type: cluster`). Application создается на каждый зарегистрированный кластер.
  - `Matrix / Merge generators` — комбинация генераторов (декартово произведение). Например, умножаем Git-генератор на Cluster-генератор.
- **Шаблон** (`template`) — это скелет объекта `Application` с поддержкой подстановок (Go Templates), например `{{.env}}` или `{{path.basename}}`. ApplicationSet-контроллер непрерывно наблюдает за генератором. Изменился генератор (добавился кластер, появился каталог в git) — контроллер *динамически* создает новый Application. Удалился элемент — Application удаляется (а с флагом `prune` уедут и все k8s ресурсы).

### 2.1 Применить ApplicationSet (List Generator)

Изучим файл `applicationset/appset.yaml`. Он использует `list` генератор:

```yaml
# Фрагмент appset.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: web-environments
  namespace: argocd
spec:
  generators:
  - list:
      elements:
      - env: dev
      - env: staging
      - env: prod
  template:
    metadata:
      name: 'web-{{env}}' # Подставляем переменную env для уникального имени
    spec:
      project: labs-gitops
      source:
        repoURL: 'https://github.com/dedanimalfarm/lern.git'
        targetRevision: main
        path: 'labs/kubernetes/modules/25-gitops-at-scale/overlays/{{env}}'
      destination:
        server: 'https://kubernetes.default.svc'
        namespace: 'lab-{{env}}'
      syncPolicy:
        automated:
          selfHeal: true
          prune: true
        syncOptions:
        - CreateNamespace=true
```

Применим проект и аппсет в кластер:

```bash
# 1. Применяем границы доверия (AppProject)
kubectl apply -f applicationset/appproject.yaml

# 2. Применяем фабрику приложений (ApplicationSet)
kubectl apply -f applicationset/appset.yaml

# Подождем несколько секунд, пока контроллер отрендерит манифесты...
sleep 5

# Проверим, что ApplicationSet породил три Application:
kubectl -n argocd get applicationset web-environments
# NAME               AGE
# web-environments   10s

kubectl -n argocd get applications
# Ожидаемый вывод:
# NAME           SYNC STATUS   HEALTH STATUS
# web-dev        Synced        Healthy
# web-prod       Synced        Healthy
# web-staging    Synced        Healthy
```

```bash
# Проверяем реальное состояние в кластере: Каждое окружение развёрнуто 
# в свой namespace с нужным числом реплик, как мы и задали в kustomize overlays:
for e in dev staging prod; do 
  echo -n "Окружение lab-$e: "
  kubectl -n lab-$e get deploy web -o custom-columns=NAME:.metadata.name,REPLICAS:.status.replicas,IMAGE:.spec.template.spec.containers[0].image --no-headers
done
# Окружение lab-dev: web   1   nginx:1.27-alpine
# Окружение lab-staging: web   2   nginx:1.27-alpine
# Окружение lab-prod: web   3   nginx:1.27.3-alpine
```

> `web-<env>` — это абсолютно обычные Argo Application'ы (их видно в UI, их можно проверять через CLI). Но "хозяином" (у них есть ownerReference) для них выступает ApplicationSet. Если вы попытаетесь изменить поле в `web-dev` напрямую, ApplicationSet-контроллер тут же перезапишет его обратно, исходя из своего шаблона.

### 2.2 Альтернатива: ApplicationSet с Git Generator

Вместо `list` генератора, где мы хардкодим список (`dev`, `staging`, `prod`), намного изящнее использовать Git Generator типа `directories`.
Он просканирует указанный путь в Git и для каждой найденной папки автоматически создаст Application.

```yaml
# Пример того, как бы выглядел Git-генератор:
spec:
  generators:
  - git:
      repoURL: https://github.com/dedanimalfarm/lern.git
      revision: main
      directories:
      - path: labs/kubernetes/modules/25-gitops-at-scale/overlays/*
  template:
    metadata:
      # Переменная path.basename автоматически берется из имени директории 
      # (будет: dev, staging, prod)
      name: 'web-{{path.basename}}' 
    spec:
      source:
        path: '{{path}}' # 'labs/kubernetes/modules/25-gitops-at-scale/overlays/dev'
        # ...
```
С таким подходом, чтобы создать QA-окружение, вам достаточно просто запушить новую папку `overlays/qa` в git. ApplicationSet обнаружит новый коммит, увидит новую папку и автоматически создаст `web-qa`. Это и есть истинный GitOps на масштабе!

### 2.3 Безопасность и изоляция через AppProject

**AppProject** — логическая группировка в Argo CD и граница доверия. Он защищает кластер: определяет, из каких репозиториев (`sourceRepos`), в какие кластеры/namespaces (`destinations`) и какие конкретно типы ресурсов (`clusterResourceWhitelist`) разрешено деплоить приложениям в этом проекте. 

В нашем примере `applicationset/appproject.yaml`:
```yaml
spec:
  sourceRepos:
  - "https://github.com/dedanimalfarm/lern.git"
  destinations:
  - namespace: 'lab-*' # Разрешаем деплой только в неймспейсы с префиксом lab-
    server: https://kubernetes.default.svc
  clusterResourceWhitelist:
  - group: ""
    kind: Namespace # Явно разрешаем создание неймспейсов
```
Если `CreateNamespace=true` для Application, namespace создается самим Argo, и это *cluster-scoped* действие, поэтому тип ресурса `Namespace` нужно явно разрешить в AppProject.

---

## Часть 3: prune и selfHeal на масштабе

### Теория: Жизненный цикл синхронизации в Argo CD

В Argo CD раздел `syncPolicy` определяет, как Argo поддерживает состояние кластера в соответствии с Git.
- `syncPolicy.automated` включает непрерывную (автоматическую) синхронизацию. Без него вам придется нажимать кнопку "Sync" руками.
- **`selfHeal: true`** — это механизм "самоизлечения" (или защиты от дрейфа). Если кто-то *руками* (через `kubectl`) изменит ресурс в кластере (сделает дрейф конфигурации), Argo CD заметит разницу и **автоматически откатит** изменения к тому состоянию, которое описано в Git.
- **`prune: true`** — это механизм сборки мусора (Garbage Collection). Если объект удален из Git-репозитория (или удален генератор из ApplicationSet), Argo CD автоматически **удалит** соответствующие ресурсы из Kubernetes кластера. Без флага `prune` брошенные объекты останутся в кластере навсегда (как orphan resources), потребляя ресурсы.

В масштабе организации комбинация `automated` + `selfHeal` + `prune` означает: **«Единственный источник правды — это Git. Любое окружение, отклонившееся от него руками, безжалостно возвращается назад; всё удалённое из Git — вычищается из кластера. Никаких уникальных "снежинок" в кластерах не существует.»**

### 3.1 selfHeal: ручной дрейф откатывается

Проверим, как система защищает себя от несанкционированного ручного вмешательства.

```bash
# Подкрутим прод окружение руками (через kubectl), вопреки Git 
# В Git (overlay prod) задано 3 реплики.
echo "Масштабируем prod руками до 7 реплик..."
kubectl -n lab-prod scale deploy web --replicas=7

# Посмотрим статус сразу:
kubectl -n lab-prod get deploy web
# Ожидаемо: 7 реплик (идет скейлинг)

echo "Ждем 10-20 секунд, пока Argo CD 'заметит' OutOfSync и включит selfHeal..."
sleep 20

# Проверяем снова:
kubectl -n lab-prod get deploy web
# NAME   READY   UP-TO-DATE   AVAILABLE   AGE
# web    3/3     3            3           2m
# Argo вернул к Git-состоянию: selfHeal отменил ручное изменение!
```

Видно в статусе Application: он кратковременно перешел в состояние `OutOfSync`, а затем контроллер снова синхронизировал его (вернул 3 реплики) и статус стал `Synced`.

```bash
kubectl -n argocd get application web-prod \
  -o jsonpath='Sync: {.status.sync.status} | Health: {.status.health.status}{"\n"}'
# Sync: Synced | Health: Healthy
```

### 3.2 prune: каскадное удаление окружения через Git

> Демонстрация: Если удалить окружение (например, `dev`) из `list` генератора в файле `applicationset/appset.yaml`, контроллер удалит `Application web-dev`. А поскольку на Application стоит каскадное удаление (через финализаторы) и настроен `prune`, все ресурсы внутри неймспейса `lab-dev` (Deployment, Service) и сам namespace также будут **каскадно уничтожены**.
> В этой лабе этот сценарий отрабатывается в `tasks/03-selfheal-prune.md`.

---

## Часть 4: Другие паттерны масштабирования (обзор)

Помимо ApplicationSet, существуют и другие архитектурные паттерны масштабирования, которые полезно знать.

### App-of-Apps vs ApplicationSet

**App-of-Apps** (Приложение приложений) — это старый, но надежный паттерн. Вы создаете один "корневой" (Root) Application, `source` которого указывает на директорию в Git. Но в этой директории лежат не манифесты Deployment/Service, а... другие YAML-манифесты `Application`! Корневой апп деплоит дочерние аппы, а те уже деплоят реальную нагрузку.

```yaml
# Пример дочернего манифеста при App-of-Apps
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: web-dev
  namespace: argocd
spec:
  # ... конфигурация dev
```

*Недостаток App-of-Apps:* Если у вас 50 кластеров, вам придется руками написать и поддерживать 50 YAML файлов `Application` в папке корневого 앱а. Это много копипасты, и при добавлении нового кластера нужно делать Pull Request с новым файлом.

**ApplicationSet** решает эту проблему: вы пишете ОДИН шаблон (`template`), а генератор (например, `cluster`) динамически создает Application'ы "на лету" прямо в памяти/etcd кластера Argo CD. Вы не храните манифесты `Application` в Git, вы храните только параметры для генератора!

### Matrix Generator: декартово произведение для Multi-Cluster

Представьте, что вы хотите развернуть 3 микросервиса (frontend, backend, auth) на 2 кластера (us-east, eu-west). Вы можете использовать матричный генератор:

```yaml
  generators:
    - matrix:
        generators:
          - git: # Находит папки микросервисов
              directories:
                - path: apps/*
          - clusters: {} # Находит все кластера, добавленные в ArgoCD
  template:
    metadata:
      name: '{{path.basename}}-{{name}}' # auth-us-east, auth-eu-west...
    spec:
      destination:
        server: '{{server}}' # URL API-сервера кластера
```
`3 apps` × `2 clusters` = 6 сгенерированных Application от одного файла ApplicationSet. При добавлении третьего кластера в ArgoCD, система автоматически развернет в нем все 3 микросервиса! Это невероятная мощь автоматизации.

---

## Часть 5: Troubleshooting — боевые инциденты на проде

При масштабировании GitOps на десятки команд и сотни приложений неизбежно возникают сложные инциденты. Рассмотрим алгоритм поиска и устранения неисправностей.

### Теория: Алгоритм диагностики ApplicationSet/Application

```text
Окружение НЕ разворачивается или сломалось
│
├─ Application вообще НЕ создан ───────► Проблема в ApplicationSet!
│  │  Команда: kubectl -n argocd describe applicationset <name>
│  │  Смотреть секцию Events:
│  │  - Генератор пуст? (Git-генератор не нашел файлы / List пуст)
│  │  - Ошибка шаблона? (опечатка в {{.field}}, если стоит missingkey=error)
│  └─ - Синтаксическая ошибка в YAML аппсета.
│
├─ Application есть, но статус Unknown/ComparisonError ─► Проблема с Git/Source!
│  │  Симптом: "path does not exist", "git repo timeout", "unknown variable".
│  └─ Команда: kubectl -n argocd get app <app> -o jsonpath='{.status.conditions}'
│
├─ OutOfSync, постоянно висит, не синхронизируется ─► Проблема с правами / AppProject!
│  │  Симптом: "project ... is not permitted", "namespace not managed".
│  └─ Решение: Проверить и исправить настройки в AppProject YAML.
│
├─ Synced, но статус Degraded / Missing ─► Проблема с k8s ресурсом!
│  │  Симптом: CrashLoopBackOff, ImagePullBackOff в подах, не хватает прав RBAC.
│  └─ Решение: Обычный k8s-траблшутинг (logs, describe pod).
│
└─ Namespace не создан ─────────► Ошибка настройки SyncOptions.
      Включен ли CreateNamespace=true? Добавлен ли Namespace в clusterResourceWhitelist 
      в политиках безопасности AppProject?
```

### Инцидент 1: ApplicationSet породил битый Application (`path does not exist`)

Оформлен как лабораторный стенд `broken/scenario-01/`. Сценарий: разработчик допустил банальную опечатку в элементе списка генератора (`stagng` вместо `staging`). Это рождает Application `web-stagng`, который ссылается на несуществующий путь в Git.

```bash
# Сымитируем инцидент:
kubectl apply -f broken/scenario-01/appset-broken.yaml

# Ждем реакции контроллера
sleep 5

# Проверим статусы: web-stagng появился, но он сломан! SYNC = Unknown
kubectl -n argocd get applications        
# web-dev        Synced        Healthy
# web-prod       Synced        Healthy
# web-stagng     Unknown       Healthy  <-- ПРОБЛЕМА

# Выясним причину через CLI (достанем conditions):
kubectl -n argocd get application web-stagng -o jsonpath='{.status.conditions[*].message}{"\n"}'
# ВЫВОД: "path /labs/kubernetes/modules/25-gitops-at-scale/overlays/stagng does not exist in the Git repository"

# Решение: исправить опечатку (stagng -> staging) в генераторе AppSet и переприменить.
kubectl apply -f solutions/01-path/appset-fixed.yaml

# ArgoCD ApplicationSet controller очень умный: он удалит сломанный web-stagng 
# и создаст правильный web-staging.
```

### Инцидент 2: AppProject запрещает развертывание (Permissions Denied)

В корпоративной среде AppProject настраивают администраторы безопасности (SecOps). Если вы попытаетесь развернуть ресурс, который не входит в `clusterResourceWhitelist` (например, `ClusterRole` или объект `Ingress`), Application останется в состоянии `OutOfSync` и выдаст ошибку: 
`Resource ... is not permitted in project ...`
**Решение:** Обратиться к администраторам за расширением прав в `AppProject`, либо убрать запрещенный ресурс из вашего Helm-чарта / Kustomize-сборки.

### Инцидент 3: Бесконечный цикл синхронизации (Flapping / OutOfSync) из-за Mutating Webhook

Очень частый инцидент на продакшене. Вы разворачиваете Deployment с 1 контейнером. Но в кластере установлен Istio, который работает как *Mutating Admission Webhook*. Он на лету инжектит второй контейнер (sidecar) `istio-proxy` в ваш под/Deployment.
Что происходит дальше:
1. ArgoCD сравнивает "Live State" (в кластере 2 контейнера) с "Git State" (в гите 1 контейнер).
2. Видит разницу (OutOfSync).
3. Запускает `selfHeal`, пытаясь удалить `istio-proxy`.
4. Istio тут же инжектит его обратно в момент создания/обновления.
5. ArgoCD снова запускает `selfHeal`. Цикл повторяется бесконечно! Кластер "горит", API Server перегружен.

**Решение:** Использовать директиву `ignoreDifferences` в спецификации Application (или ApplicationSet), чтобы сказать ArgoCD: "не обращай внимание на изменения в этом конкретном JSON-пути ресурса".
```yaml
ignoreDifferences:
- group: apps
  kind: Deployment
  jqPathExpressions:
  - '.spec.template.spec.containers[] | select(.name == "istio-proxy")'
```

### Инцидент 4: Конфликт имён (Collision) при генерации Application

Если генератор в ApplicationSet формирует одинаковые имена для `Application` (например, два кластера называются одинаково в Secret-ах), контроллер выдаст ошибку `Application ... already exists and is not owned by this ApplicationSet`. 
Внимательно проверяйте шаблонизацию в `metadata.name: '{{cluster}}-{{app}}'`, чтобы ключи были гарантированно уникальными для каждого инстанса.

### Бонус: быстрая CLI диагностика

Полезные алиасы и команды для дебага без использования UI-интерфейса ArgoCD (отлично подходит для CI/CD пайплайнов):

```bash
# Получить список всех Application, их статус синхронизации и здоровья (компактно)
kubectl -n argocd get applications \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status

# Почему конкретный Application не синхронизируется? (Выводит все Conditions)
kubectl -n argocd get application web-prod \
  -o jsonpath='{range .status.conditions[*]}{.type}: {.message}{"\n"}{end}'

# Просмотр логов контроллера ApplicationSet (если Application вообще не создаются)
kubectl -n argocd logs -l app.kubernetes.io/name=argocd-applicationset-controller --tail=50 | grep error

# Что нагенерил ApplicationSet (и есть ли ошибки генератора/шаблона) в Events
kubectl -n argocd describe applicationset web-environments | tail -20
```

---

## Проверка модуля

Убедитесь, что все окружения корректно запущены и функционируют согласно настройкам Kustomize и ApplicationSet.

```bash
# Развернуть, если ещё не сделано в Части 2:
kubectl apply -f applicationset/appproject.yaml
kubectl apply -f applicationset/appset.yaml

# Автопроверка с помощью тестового скрипта
# (Скрипт ждёт Synced/Healthy для всех аппов и проверяет количество реплик по окружениям)
bash verify/verify.sh

# Ожидаемый вывод:
# [INFO] Checking Argo CD components...
# [OK] applicationset/web-environments present
# [OK] appproject/labs-gitops present
# [INFO] Waiting for Applications to be Healthy and Synced (timeout 60s)...
# [OK] web-dev Synced/Healthy, deploy web in lab-dev has 1 replica(s)
# [OK] web-staging Synced/Healthy, deploy web in lab-staging has 2 replica(s)
# [OK] web-prod Synced/Healthy, deploy web in lab-prod has 3 replica(s)
# [OK] module 25 verified successfully!
```

---

## Финальная карта ресурсов модуля

Визуализируем, какие объекты мы создали в Kubernetes и за что они отвечают:

| Имя Ресурса | Тип Объекта (Kind) | Неймспейс | Роль и назначение |
|-------------|--------------------|-----------|-------------------|
| `web-environments` | **ApplicationSet** | `argocd` | Фабрика. Содержит `list`-генератор и шаблон; динамически порождает 3 объекта Application. |
| `labs-gitops` | **AppProject** | `argocd` | Безопасность. Граница доверия, разрешающая деплой в `lab-*` namespaces из конкретного github-репо. |
| `web-dev` <br> `web-staging` <br> `web-prod` | **Application** | `argocd` | Контроллеры. Отслеживают изменения в `overlays/<env>` и синхронизируют их в кластер. Управляются ApplicationSet. |
| `web` | **Deployment** + **Service** | `lab-dev` <br> `lab-staging` <br> `lab-prod` | Конечная полезная нагрузка. Разное количество реплик (1, 2, 3), запущенная в разных окружениях. |
| `base/` + `overlays/*` | **Git Files** (Kustomize) | - (в Git) | Единый источник правды (SSOT) с дельтами окружений, который Argo CD читает при рендере. |

---

## Теоретические вопросы (итоговые)

Для самопроверки убедитесь, что можете уверенно ответить на следующие вопросы:

### Блок 1: Kustomize
1. `base` vs `overlay` — кто на кого ссылается? Какая директива в yaml для этого используется?
2. Какими трансформерами (блоками в `kustomization.yaml`) overlay меняет количество реплик у Deployment и тег образа?
3. В чём фундаментальная разница подходов Kustomize и Helm? Когда лучше использовать один, а когда другой?
4. Зачем в Kustomize нужна директива `namePrefix` и чем она опасна при обновлении существующего релиза в продакшене?
5. В каком порядке применяются патчи, если их несколько для одного и того же ресурса?

### Блок 2: ApplicationSet
6. Что делает `list`-генератор и чем его можно заменить для автоматического сканирования каталогов в Git?
7. Что произойдёт с объектами `Application` в кластере при добавлении нового или удалении существующего элемента в массиве генератора?
8. Зачем нужен AppProject? Перечислите 3 типа ограничений, которые в нем можно задать для защиты кластера.
9. Почему создание Namespace (`CreateNamespace=true` в `syncOptions`) требует добавления ресурса типа Namespace в `clusterResourceWhitelist` AppProject'а?

### Блок 3: GitOps на масштабе
10. `selfHeal` vs `prune` — в чем разница? Приведите пример инцидента, когда может сработать одно, но не сработать другое.
11. Почему ручной `kubectl edit` или `kubectl scale` работающего окружения — антипаттерн в строгом GitOps подходе?
12. App-of-Apps vs ApplicationSet — в каких сценариях масштабирования вы выберете каждый из паттернов?
13. Что такое Flapping (бесконечный цикл синхронизации) в контексте Mutating Webhooks и `selfHeal`? Как директива `ignoreDifferences` помогает решить эту проблему?

---

## Практические задания (отработка)

Для закрепления навыков выполните сценарии в директории `tasks/`. Для их выполнения вам потребуется сделать изменения в файлах и выполнить `git commit` + `git push` в ваш форк/репозиторий (иначе Argo CD их не увидит, ведь он читает только из Git).

1. **Базовый Kustomize (`tasks/01-kustomize-overlays.md`)** — Рендер overlays локально, сравнение дельт через diff, ручной `apply -k` для проверки гипотез.
2. **Освоение AppSet (`tasks/02-applicationset.md`)** — Развертывание ApplicationSet. Добавьте новое окружение `env: qa` в list-генератор, создайте для него overlay и убедитесь, что Argo CD автоматически создал Application и namespace.
3. **Война дрейфов (`tasks/03-selfheal-prune.md`)** — Спровоцируйте дрейф, изменив лимиты памяти в deployment через kubectl, и наблюдайте, как `selfHeal` откатывает их. Затем удалите env из списка генератора и проверьте каскадный `prune`.
4. **Git Generator (Advanced)**: Самостоятельно перепишите `appset.yaml`, заменив `list`-генератор на `git` directory generator. Запушьте изменения. Убедитесь, что система продолжила работать без сбоев (старые Application удалились, новые создались, ресурсы в кластере пересоздались или остались нетронутыми в зависимости от конфигурации).
5. **Тестирование патчей**: Добавьте в `prod` overlay секцию `patchesStrategicMerge` (или `patches`), которая внедряет новую переменную окружения (например, `CACHE_ENABLED=true`) в контейнер `nginx`. Проверьте, что изменения применились только в `lab-prod`, не затронув `dev` и `staging`.

---

## Шпаргалка

Самые частые и полезные команды для работы с Kustomize и Argo CD ApplicationSet:

```bash
# === Kustomize CLI ===
# Отрендерить манифесты (эквивалент helm template) и вывести в консоль:
kubectl kustomize overlays/<env>

# Отрендерить и сразу применить напрямую (bypass Argo CD - полезно для локального дебага):
kubectl apply -k overlays/<env>

# Задать новый image tag через CLI (автоматически модифицирует kustomization.yaml):
cd overlays/prod && kustomize edit set image nginx=nginx:1.28-alpine

# Добавить новый ресурс в kustomization.yaml через CLI:
kustomize edit add resource secret.yaml

# === Argo CD ApplicationSet / Application ===
# Развернуть или обновить ApplicationSet и AppProject:
kubectl apply -f applicationset/appproject.yaml -f applicationset/appset.yaml

# Посмотреть всю иерархию (кто кем управляет):
kubectl -n argocd get applicationset,applications

# Краткий статус синхронизации и здоровья (очень полезно для CI/CD):
kubectl -n argocd get application <app> \
  -o jsonpath='{.status.sync.status}/{.status.health.status}{"\n"}'

# Принудительная синхронизация (если автоматическая отключена):
argocd app sync web-dev # требует установленного CLI argocd

# Принудительное удаление зависшего Application (снять финализаторы):
kubectl -n argocd patch app web-dev -p '{"metadata": {"finalizers": null}}' --type merge

# === Диагностика и Траблшутинг ===
# Посмотреть, какие именно параметры сгенерировал ApplicationSet (полезно при matrix):
kubectl -n argocd describe applicationset web-environments | tail -20

# Вытащить все ошибки (Conditions) из Application (почему он сломан?):
kubectl -n argocd get application <app> \
  -o jsonpath='{range .status.conditions[*]}{.type}: {.message}{"\n"}{end}'

# Просмотр логов контроллера ApplicationSet (grep по ошибкам):
kubectl -n argocd logs -l app.kubernetes.io/name=argocd-applicationset-controller --tail=100 | grep error

# === Уборка модуля ===
# Удаление ApplicationSet с каскадным удалением дочерних Application и всех их ресурсов:
kubectl -n argocd delete applicationset web-environments
kubectl -n argocd delete appproject labs-gitops
# На всякий случай подчищаем неймспейсы (если prune не сработал):
kubectl delete ns lab-dev lab-staging lab-prod --ignore-not-found
```

---

## Чему вы научились

В этом расширенном модуле вы вышли за рамки простого деплоя одного приложения и погрузились в **настоящий GitOps на масштабе Enterprise**. Вы научились:
- Глубоко понимать архитектуру Argo CD и роль `argocd-repo-server`.
- Использовать парадигму `Base & Overlays` Kustomize для чистого и декларативного управления множеством окружений (multi-env) без шаблонизаторов и дублирования кода.
- Разворачивать фабрики приложений с помощью `Argo CD ApplicationSet`, понимая работу различных генераторов (List, Git, Matrix).
- Защищать кластер от ручных вмешательств (`selfHeal`) и автоматизировать сборку мусора (`prune`).
- Ограничивать права деплоя и радиус поражения через `AppProject`.
- Диагностировать сложные распределенные инциденты (отсутствие путей, конфликты имён, бесконечные циклы синхронизации Mutating Webhooks).
- Использовать продвинутые команды CLI для быстрого получения статусов и метрик синхронизации.

## Уборка

Перед переходом к следующему модулю очистите стенд, чтобы освободить ресурсы и избежать конфликтов в будущем.

```bash
# Удаление ApplicationSet каскадно удаляет порождённые Application.
# Если на них настроен prune (и есть финализаторы), это приведет к удалению 
# всех Deployments/Services в целевых неймспейсах.
kubectl -n argocd delete applicationset web-environments --ignore-not-found

# Удаляем Project
kubectl -n argocd delete appproject labs-gitops --ignore-not-found

# Удаляем сами неймспейсы для гарантии чистоты эксперимента
kubectl delete ns lab-dev lab-staging lab-prod --ignore-not-found
```

> **Дальше по ROADMAP:** Следующий шаг — **Progressive Delivery** (Прогрессивная доставка). Вы изучите `Argo Rollouts`, научитесь делать Canary и Blue-Green развертывания без простоев, а также настраивать автоматический анализ метрик (Prometheus) для принятия решения о продвижении или автоматическом откате (rollback) релиза. Это следующий слой зрелости над базовой GitOps-доставкой!
