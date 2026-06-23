import sys

content = """# Лабораторная работа 25: GitOps на масштабе (Kustomize overlays, ApplicationSet, multi-env)

## Оглавление
<!-- TOC -->
- [Предварительные требования](#предварительные-требования)
- [Стартовая проверка](#стартовая-проверка)
- [Архитектурный обзор: GitOps на масштабе](#архитектурный-обзор-gitops-на-масштабе)
- [Часть 1: Kustomize — base и overlays](#часть-1-kustomize--base-и-overlays)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-1)
  - [1.1 Рендер overlays](#11-рендер-overlays)
  - [1.2 Создание нового overlay с нуля (QA окружение)](#12-создание-нового-overlay-с-нуля-qa-окружение)
- [Часть 2: ApplicationSet — один объект, много Application](#часть-2-applicationset--один-объект-много-application)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-2)
  - [2.1 Применить ApplicationSet (List Generator)](#21-применить-applicationset-list-generator)
  - [2.2 Альтернатива: ApplicationSet с Git Generator](#22-альтернатива-applicationset-с-git-generator)
- [Часть 3: prune и selfHeal на масштабе](#часть-3-prune-и-selfheal-на-масштабе)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-3)
  - [3.1 selfHeal: ручной дрейф откатывается](#31-selfheal-ручной-дрейф-откатывается)
  - [3.2 prune: удаление окружения через Git](#32-prune-удаление-окружения-через-git)
- [Часть 4: Другие паттерны масштабирования (обзор)](#часть-4-другие-паттерны-масштабирования-обзор)
  - [App-of-Apps vs ApplicationSet](#app-of-apps-vs-applicationset)
  - [Matrix Generator: декартово произведение](#matrix-generator-декартово-произведение)
- [Часть 5: Troubleshooting — боевые инциденты](#часть-5-troubleshooting--боевые-инциденты)
  - [Теория: алгоритм диагностики ApplicationSet/Application](#теория-алгоритм-диагностики-applicationsetapplication)
  - [Инцидент 1: ApplicationSet породил битый Application (`path does not exist`)](#инцидент-1-applicationset-породил-битый-application-path-does-not-exist)
  - [Инцидент 2: AppProject запрещает развертывание (Permissions Denied)](#инцидент-2-appproject-запрещает-развертывание-permissions-denied)
  - [Инцидент 3: Бесконечный цикл синхронизации (Flapping / OutOfSync) из-за Mutating Webhook](#инцидент-3-бесконечный-цикл-синхронизации-flapping--outofsync-из-за-mutating-webhook)
  - [Инцидент 4: Конфликт имён (Collision) при генерации](#инцидент-4-конфликт-имён-collision-при-генерации)
  - [Бонус: быстрая CLI диагностика](#бонус-быстрая-cli-диагностика)
- [Проверка модуля](#проверка-модуля)
- [Финальная карта ресурсов модуля](#финальная-карта-ресурсов-модуля)
- [Теоретические вопросы (итоговые)](#теоретические-вопросы-итоговые)
- [Практические задания (отработка)](#практические-задания-отработка)
- [Шпаргалка](#шпаргалка)
- [Чему вы научились](#чему-вы-научились)
- [Уборка](#уборка)
<!-- /TOC -->


> ⏱ время ~60 мин · сложность 4/5 · пререквизиты: Трек 1 (Core), Helm, Argo CD базовый уровень

Цель: научиться разворачивать ОДНО приложение в МНОГО окружений без копипасты — через `Kustomize` (base + overlays на dev/staging/prod/qa) и Argo CD `ApplicationSet` (один объект порождает множество Application на каждое окружение или кластер). К концу модуля вы будете глубоко понимать разницу base/overlay, возможности генераторов ApplicationSet (List, Git, Matrix), алгоритмы синхронизации `prune`/`selfHeal`, а также научитесь диагностировать сложные сбои на масштабе (отсутствие путей, нехватка прав в AppProject, бесконечные циклы синхронизации).

> Развитие модуля 09 (Helm + Argo CD Application — один деплой). Здесь — масштаб: много окружений из одного источника. Концепции Sync-waves и хуков применимы и тут. Reconcile Application-контроллера — модель из модуля 01, возведённая в степень.

> ⚠️ **GitOps тянет из git, а не из вашей локальной папки.** Argo CD синхронизирует манифесты из вашего git-репозитория. Любая правка overlay или ApplicationSet видна Argo только ПОСЛЕ `git push`. Эта лаба спроектирована так, чтобы базовый сценарий работал «из коробки», но для выполнения дополнительных заданий свои изменения обязательно нужно коммитить и пушить.

---

## Предварительные требования

Перед началом работы убедитесь, что ваш кластер готов к GitOps-нагрузкам. Нам потребуется рабочий Kubernetes кластер, установленный Argo CD и плагины Kustomize.

```bash
# kubeconfig нашего кластера (Kubespray); на другом стенде — свой путь/контекст
export KUBECONFIG=/root/.kube/kubespray.conf

# Проверяем доступность API-сервера
kubectl cluster-info

# В Argo CD версии 2.0+ ApplicationSet контроллер поставляется "из коробки" 
# (раньше его приходилось ставить отдельно). Убедимся, что он запущен:
kubectl -n argocd get deploy argocd-applicationset-controller
# Ожидаемый вывод:
# NAME                               READY   UP-TO-DATE   AVAILABLE   AGE
# argocd-applicationset-controller   1/1     1            1           ...

# Проверим сам Argo CD server и repo-server (он отвечает за рендер манифестов)
kubectl -n argocd get pods -l app.kubernetes.io/name=argocd-repo-server

# kustomize встроен в kubectl (kubectl kustomize / kubectl apply -k),
# но иногда полезно иметь standalone kustomize CLI для advanced-фич.
kubectl version -o json | grep -m1 gitVersion   # v1.36.1 или выше
```

**Почему `argocd-repo-server` важен?** 
Именно этот компонент клонирует ваш репозиторий, запускает команду `kustomize build` (или `helm template`) и возвращает сырой YAML обратно в `argocd-application-controller`, который уже сравнивает этот YAML с текущим состоянием кластера.

---

## Стартовая проверка

Убедимся, что кластер чист и готов к лабораторной работе.

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
│   ├── deployment.yaml
│   ├── service.yaml
│   └── kustomization.yaml   # Указывает, что объединять в base
├── overlays/                # Точечные патчи на каждое окружение
│   ├── dev/                 # (replicas 1, ns lab-dev)
│   │   ├── kustomization.yaml
│   │   └── patch-replicas.yaml
│   ├── staging/             # (replicas 2, ns lab-staging)
│   └── prod/                # (replicas 3, ns lab-prod, фиксация версии образа)
└── applicationset/
    ├── appproject.yaml      # AppProject: Граница доверия и секурити-политики
    └── appset.yaml          # ApplicationSet: list-генератор -> 3 Application
```

---

## Архитектурный обзор: GitOps на масштабе

В этом модуле мы соединяем две мощные технологии: Kustomize (для управления конфигурациями без шаблонизации) и Argo CD ApplicationSet (для автоматизации создания контроллеров развертывания). 

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

**Ключевые принципы:**
1. **DRY (Don't Repeat Yourself)**: Базовые манифесты лежат в одном месте (`base/`). Окружения содержат только отличия (дельты).
2. **Бесшовная автоматизация**: При добавлении нового окружения вам не нужно писать новый `Application`. Вы просто добавляете папку `overlays/new-env` и обновляете генератор в `ApplicationSet`.
3. **Безопасность (Boundary)**: `AppProject` жестко ограничивает, какие кластеры, неймспейсы и типы ресурсов могут быть развернуты.

---

## Часть 1: Kustomize — base и overlays

### Теория для изучения перед частью

- **Kustomize** собирает манифесты БЕЗ использования языков шаблонизации (в отличие от Helm и его Go-templates). Это называется *template-free customization*. Вы оперируете чистыми YAML-файлами. Есть `base` (общие, полностью рабочие манифесты) и `overlays` (патчи поверх base). `kubectl kustomize <dir>` генерирует итоговый YAML, а `kubectl apply -k <dir>` применяет его.
- **kustomization.yaml** — главный файл Kustomize. Он может включать:
  - `resources`: ссылки на файлы или папки (например, `../../base`).
  - `namespace`: переопределение неймспейса для всех ресурсов.
  - `namePrefix` / `nameSuffix`: добавление префиксов/суффиксов ко всем именам.
  - `commonLabels` / `commonAnnotations`: добавление меток ко всем объектам (и селекторам!).
  - `images`: подмена тегов или репозиториев (например, `nginx:latest` -> `nginx:1.27.3-alpine`).
  - `patches` (ранее `patchesStrategicMerge` / `patchesJson6902`): наложение изменений (например, изменить количество реплик или добавить переменную окружения).
- **Зачем это нужно:** Dev, Staging и Prod окружения отличаются очень малым набором параметров: число реплик, теги образов Docker, лимиты ресурсов CPU/RAM, хосты Ingress. Держать три полные копии файлов Deployment/Service/Ingress — значит обречь себя на ошибки ("поправили лейбл в dev, но забыли в prod"). Kustomize решает эту проблему элегантно: Base+overlay = один источник правды + явная дельта на окружение.
- **Kustomize vs Helm:** Helm — это пакетный менеджер. Он использует шаблонизацию текста (text-templating). Это мощно, но иногда приводит к "лапше" из `{{ if eq .Values.env "prod" }}`. Kustomize работает на уровне структуры YAML. Argo CD нативно поддерживает оба инструмента, и часто их комбинируют: Helm рендерит вендорный chart, а Kustomize патчит его под специфику компании (через `helmGlobals` или Kustomize Helm Chart Inflation).

### 1.1 Рендер overlays

Давайте посмотрим, как `kustomize` объединяет base и overlays на лету. Мы просто выводим результат в терминал (рендеринг), не применяя его в кластер.

```bash
# Посмотрим, что именно меняет каждый overlay:
for e in dev staging prod; do
  echo -e "\n\033[1;34m== Рендер окружения: $e ==\033[0m"
  # Мы фильтруем вывод, чтобы показать только самые важные измененные поля
  kubectl kustomize overlays/$e | grep -E 'namespace:|replicas:|image:|env:'
done

# Ожидаемый вывод:
# == Рендер окружения: dev ==
#       env: dev
#       image: nginx:1.27-alpine
#   namespace: lab-dev
#   replicas: 1
# 
# == Рендер окружения: staging ==
#       env: staging
#       image: nginx:1.27-alpine
#   namespace: lab-staging
#   replicas: 2
# 
# == Рендер окружения: prod ==
#       env: prod
#       image: nginx:1.27.3-alpine
#   namespace: lab-prod
#   replicas: 3
```

Видно: каталог `base` один, но мы получаем три совершенно разных манифеста. Дельта на окружение — только replicas, namespace, метка `env` и (в prod) жестко запиненный тег образа для надежности.

Вы можете применить одно окружение напрямую через kubectl (kustomize встроен в него), без использования Argo CD:

```bash
# dry-run=client создает YAML для неймспейса, который мы пайпим в kubectl apply
kubectl create ns lab-dev --dry-run=client -o yaml | kubectl apply -f -

# -k указывает kubectl использовать kustomize для директории
kubectl apply -k overlays/dev

# Проверяем результат:
kubectl -n lab-dev get deploy web      
# NAME   READY   UP-TO-DATE   AVAILABLE   AGE
# web    1/1     1            1           10s

# Уборка ручного применения, так как дальше мы доверим это Argo CD
kubectl delete -k overlays/dev         
kubectl delete ns lab-dev
```

### 1.2 Создание нового overlay с нуля (QA окружение)

Попробуем самостоятельно создать конфигурацию для QA-окружения, используя существующий `base`.

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

# Патчим образ (указываем конкретный тег, который тестируют QA)
images:
  - name: nginx
    newTag: "1.26-alpine"

# Применяем патч для реплик
patches:
  - path: patch-replicas.yaml
