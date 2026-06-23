# Лабораторная работа 28: Multi-tenancy и стоимость — HNC, vcluster и FinOps

## Оглавление
<!-- TOC -->
- [Цели](#цели)
- [Предварительные требования](#предварительные-требования)
- [Стартовая проверка](#стартовая-проверка)
- [Часть 1: Спектр изоляции тенантов](#часть-1-спектр-изоляции-тенантов)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью)
  - [1.1 Архитектура изоляции: Control Plane vs Data Plane](#11-архитектура-изоляции-control-plane-vs-data-plane)
- [Часть 2: Иерархические namespace (HNC)](#часть-2-иерархические-namespace-hnc)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-1)
  - [2.1 Иерархия и наследование RBAC](#21-иерархия-и-наследование-rbac)
  - [2.2 Субнеймспейсы через якорь](#22-субнеймспейсы-через-якорь)
  - [2.3 Распространение произвольных ресурсов](#23-распространение-произвольных-ресурсов)
  - [2.4 Защита от выстрела в ногу](#24-защита-от-выстрела-в-ногу)
- [Часть 3: Виртуальные кластеры (vcluster)](#часть-3-виртуальные-кластеры-vcluster)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-2)
  - [3.1 Архитектура Syncer-паттерна](#31-архитектура-syncer-паттерна)
  - [3.2 Доступ внутрь и первый под](#32-доступ-внутрь-и-первый-под)
  - [3.3 Синхронизация Ingress и сервисов](#33-синхронизация-ingress-и-сервисов)
  - [3.4 Host-квота против тенанта](#34-host-квота-против-тенанта)
- [Часть 4: Стоимость namespace (FinOps)](#часть-4-стоимость-namespace-finops)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-3)
  - [4.1 Философия аллокации расходов в Kubernetes](#41-философия-аллокации-расходов-в-kubernetes)
  - [4.2 Стоимость по namespace (showback)](#42-стоимость-по-namespace-showback)
  - [4.3 Overprovisioning (rightsizing) и Idle-налог](#43-overprovisioning-rightsizing-и-idle-налог)
- [Часть 5: Troubleshooting (Комплексные сценарии)](#часть-5-troubleshooting-комплексные-сценарии)
  - [Сценарий 5.1: Каскадный отказ создания namespace из-за падения HNC webhook](#сценарий-51-каскадный-отказ-создания-namespace-из-за-падения-hnc-webhook)
  - [Сценарий 5.2: vcluster Syncer отклоняет поды из-за Mutating Webhooks хоста](#сценарий-52-vcluster-syncer-отклоняет-поды-из-за-mutating-webhooks-хоста)
  - [Сценарий 5.3: CoreDNS внутри vcluster не резолвит внешние ресурсы](#сценарий-53-coredns-внутри-vcluster-не-резолвит-внешние-ресурсы)
  - [Сценарий 5.4: FinOps метрики показывают нули для Init-контейнеров](#сценарий-54-finops-метрики-показывают-нули-для-init-контейнеров)
  - [Краткая таблица частых ошибок](#краткая-таблица-частых-ошибок)
- [Практические задания (отработка)](#практические-задания-отработка)
- [Проверка модуля](#проверка-модуля)
- [Шпаргалка](#шпаргалка)
- [Финальная карта ресурсов модуля](#финальная-карта-ресурсов-модуля)
<!-- /TOC -->

⏱ время: 90–120 мин · 🎚 сложность: продвинутая · ⚙️ пререквизиты: модули 06 (квоты/LimitRange), 07 (RBAC), 12 (resource management), 17 (Prometheus)

## Цели

1. **Глубоко понять спектр изоляции тенантов**: от общего namespace (soft multi-tenancy) до выделенного виртуального кластера (hard multi-tenancy). Понимать, в каких бизнес-сценариях уместен каждый подход.
2. **Освоить управление деревом namespace'ов через HNC**: как работает наследование политик безопасности, RBAC и других ресурсов, а также создание субнеймспейсов без предоставления кластерных прав командам разработки.
3. **Развернуть и администрировать виртуальный кластер (vcluster)**: разобраться в архитектуре syncer-паттерна, поднять свой API-сервер тенанта внутри одного хостового namespace и отладить взаимодействие "теневых" ресурсов с хостом.
4. **Увидеть на практике работу host-контрактов**: убедиться, что сколь угодно сильная изоляция на уровне Control Plane (vcluster) не отменяет физических лимитов и квот на уровне Data Plane.
5. **Внедрить базовые практики FinOps**: научиться считать стоимость каждого namespace по зарезервированным ресурсам (requests - showback), находить overprovisioning и выявлять так называемый "налог на простой" (idle cost).

## Предварительные требования

Для прохождения этой лаборатории мы используем завендоренные компоненты, чтобы исключить влияние внешних сбоев (например, недоступность GitHub или Docker Hub). 

```bash
export KUBECONFIG=/root/.kube/kubespray.conf   # наш стенд; на другом кластере — свой путь

# В lab должны действовать стандартные квоты стенда.
# Убеждаемся в наличии квот; если их нет — применяем.
kubectl -n lab get quota lab-quota || bash ../../scripts/bootstrap/01-apply-quotas.sh

# Применяем компоненты модуля (HNC v1.1.0 + vcluster 0.34.2, всё vendored):
kubectl apply -f manifests/

# Дожидаемся готовности компонентов. HNC может занимать некоторое время для генерации сертификатов.
kubectl -n hnc-system rollout status deploy/hnc-controller-manager --timeout=180s

# Виртуальный кластер (StatefulSet) должен запуститься внутри namespace lab.
kubectl -n lab rollout status sts/my-vcluster --timeout=300s
```

## Стартовая проверка

Убедимся, что все контроллеры живы и готовы к работе:

```bash
kubectl get ns hnc-system && kubectl -n lab get sts my-vcluster
# Ожидаемый вывод:
# NAME          READY   AGE
# my-vcluster   1/1     2m
```

---

## Часть 1: Спектр изоляции тенантов

### Теория для изучения перед частью

Когда один кластер Kubernetes предоставляется нескольким командам, проектам или окружениям (тенантам), архитекторы всегда выбирают компромисс между изоляцией, операционной сложностью и стоимостью инфраструктуры. 

В традиционном понимании, тенант — это логический потребитель платформы, который должен считать, что кластер принадлежит только ему, и при этом не иметь возможности сломать работу соседей.

```text
Слабее изоляция ◄──────────────────────────────────────────► Сильнее изоляция
Ниже стоимость  ◄──────────────────────────────────────────► Выше стоимость
Меньше overhead ◄──────────────────────────────────────────► Больше overhead

Общий Namespace    Namespace на тенанта    Иерархия NS (HNC)      vcluster               Отдельный кластер
(метки/RBAC)       + Quota/NetPol/PSA      (Деревья политик)      (Свой API Server)      (Полный Isolation)
   m01-m07              Project E              Часть 2                Часть 3               (Вне курса)
```

| Подход | Что своё у тенанта | Что общее | Когда уместен |
|--------|--------------------|-----------|---------------|
| **Namespace + RBAC/quota/netpol (Soft)** | Объекты внутри ns | API-сервер, CRD, версия k8s, ноды | Команды одной организации, доверие высокое, нет нужды в своих CRD. |
| **Иерархия ns (HNC)** | Поддерево ns, каскадные политики | То же, что выше | Крупные компании, сложная орг. структура (отдел -> команда -> проект). |
| **vcluster (Hard)** | СВОЙ API-сервер, СВОИ CRD, свой RBAC-мир | Ноды, kubelet, ядро ОС, физическая сеть | Тенанту нужен cluster-admin (для CRD, операторов), PaaS-провайдеры, "кластер напрокат". |
| **Отдельный кластер** | Всё (Control Plane + Data Plane) | Ничего | Строгая регуляторика (PCI-DSS), blast radius (ядро платформы), разные продукты. |

### 1.1 Архитектура изоляции: Control Plane vs Data Plane

Ключевая мысль, которую необходимо усвоить: **изоляция API (Control Plane) ≠ изоляция ресурсов (Data Plane)**.

- **Control Plane Isolation**: Управляет тем, *кто* может создавать ресурсы и *какие* API-эндпоинты они видят. Vcluster предоставляет 100% изоляцию Control Plane (тенант не видит чужих пространств имен или CRD).
- **Data Plane Isolation**: Управляет тем, *где* физически выполняются поды, *какую* сеть они используют и *сколько* RAM/CPU потребляют. Даже в vcluster поды в итоге работают на общих нодах хостового кластера, в общей SDN-сети (если не настроены NetworkPolicies) и делят одно ядро Linux.

**Контрольные вопросы:**
1. Чем *soft multi-tenancy* принципиально ограничен в отношении CRD (Custom Resource Definitions)?
2. Почему модель "namespace на тенанта" обходится дешевле vcluster, а vcluster значительно дешевле создания отдельного кластера на тенанта?
3. Какой фундаментальный компонент Kubernetes остается общим у ВСЕХ вариантов, кроме предоставления выделенного физического/виртуального кластера?
4. Можете ли вы назвать сценарий, когда vcluster не поможет, и потребуется выделенный кластер?

---

## Часть 2: Иерархические namespace (HNC)

### Теория для изучения перед частью

Kubernetes изначально проектировался с плоской структурой пространств имен (namespaces). Это создает проблему при масштабировании: если у вас есть департамент Frontend с 10 проектами и департамент Backend с 15 проектами, выдать общие права на весь Frontend без дублирования RoleBinding в 10 namespace'ов становится нетривиальной задачей.

**HNC (Hierarchical Namespace Controller)** решает эту проблему, добавляя namespace'ам графовые отношения "родитель → ребенок":

- **Propagation (Распространение):** объекты родителя (по умолчанию Role и RoleBinding) автоматически копируются во все дочерние ns и поддерживаются в актуальном состоянии. Выдали команде права на корневой ns (родительский) — они мгновенно появляются во всех её средах.
- **HierarchyConfiguration:** это singleton-объект с именем `hierarchy` В ДОЧЕРНЕМ ns, имеющий поле `spec.parent`. Так осуществляется вкладывание УЖЕ существующего namespace в другой.
- **SubnamespaceAnchor:** это "якорь" В РОДИТЕЛЬСКОМ ns. HNC реагирует на него и *сам* создает одноименный дочерний namespace. Это элегантный способ дать командам право заводить себе среды БЕЗ выдачи опасного cluster-level права `create namespaces`.
- Дерево видно по специальным меткам, которые HNC добавляет на namespace: `<родитель>.tree.hnc.x-k8s.io/depth`.

> ⚠️ **Важно**: Аннотацию `hnc.x-k8s.io/subnamespace-of` руками не ставят. Её поддерживает контроллер для созданных через якорь субнеймспейсов. Иерархию она НЕ задает.

> 📦 **Архивный статус**: Проект HNC переехал в архив (`kubernetes-retired`), однако концепция иерархии и propagation остается блестящей учебной моделью. В продакшене сегодня чаще используют решения вроде Capsule, Kyverno (с политиками генерации) или vcluster (Часть 3). Манифест v1.1.0 vendored в `manifests/02-hnc.yaml` — и отлично работает на k8s 1.36.

### 2.1 Иерархия и наследование RBAC

Давайте создадим базовую иерархию вручную.

```bash
# Создаем два независимых namespace
kubectl create ns parent-ns
kubectl create ns child-ns

# Задаем иерархию, поместив HierarchyConfiguration в child-ns
kubectl apply -f - <<'YAML'
apiVersion: hnc.x-k8s.io/v1alpha2
kind: HierarchyConfiguration
metadata:
  name: hierarchy
  namespace: child-ns
spec:
  parent: parent-ns
YAML

# Выдаем права на редактирование (RoleBinding) только в родительском ns
kubectl create rolebinding team-edit -n parent-ns --clusterrole=edit --user=dev-lead
sleep 5

# Проверяем дочерний ns
kubectl get rolebinding -n child-ns
```

Ожидаемый вывод:
```text
NAME        ROLE               AGE
team-edit   ClusterRole/edit   9s
```

RoleBinding был создан ТОЛЬКО в `parent-ns`, но в `child-ns` его прозрачно скопировал HNC. Дерево можно легко отследить по меткам:

```bash
kubectl get ns child-ns -o jsonpath='{.metadata.labels}' | jq
# Вы увидите метки вида:
# "child-ns.tree.hnc.x-k8s.io/depth": "0"
# "parent-ns.tree.hnc.x-k8s.io/depth": "1"
```

### 2.2 Субнеймспейсы через якорь

Вместо того чтобы просить администратора создать namespace, команда с доступом к `parent-ns` может создать "якорь".

```bash
kubectl apply -f - <<'YAML'
apiVersion: hnc.x-k8s.io/v1alpha2
kind: SubnamespaceAnchor
metadata:
  name: team-a-dev
  namespace: parent-ns
YAML
sleep 5

# HNC сам создал полноценный ns и проставил служебную аннотацию:
kubectl get ns team-a-dev -o jsonpath='{.metadata.annotations.hnc\.x-k8s\.io/subnamespace-of}{"\n"}'
# Вывод: parent-ns

# RBAC родителя уже там:
kubectl get rolebinding team-edit -n team-a-dev
```

### 2.3 Распространение произвольных ресурсов

По умолчанию HNC распространяет только Role и RoleBinding. Но мы можем настроить его так, чтобы он копировал секреты, ConfigMap'ы или NetworkPolicies. Это делается через глобальный объект `HNCConfiguration`.

```bash
# Разрешим распространять секреты
kubectl apply -f - <<'YAML'
apiVersion: hnc.x-k8s.io/v1alpha2
kind: HNCConfiguration
metadata:
  name: config
spec:
  resources:
  - group: ""
    resource: secrets
    mode: Propagate
YAML

# Создадим Secret в родительском ns
kubectl create secret generic shared-creds --from-literal=password=supersecret -n parent-ns
sleep 5

# Секрет должен появиться в child-ns!
kubectl get secret shared-creds -n child-ns
```

### 2.4 Защита от выстрела в ногу

Вебхук HNC очень строго валидирует иерархию НА ВХОДЕ. Вы не можете создать циклическую зависимость или задать несуществующего родителя.

```bash
kubectl apply -f - <<'YAML'
apiVersion: hnc.x-k8s.io/v1alpha2
kind: HierarchyConfiguration
metadata:
  name: hierarchy
  namespace: child-ns
spec:
  parent: does-not-exist-ns
YAML
```

Вывод:
```text
Error from server (Forbidden): ... admission webhook "hierarchyconfigurations.hnc.x-k8s.io" denied the request:
... "hierarchy" is forbidden: requested parent "does-not-exist-ns" does not exist
```

**Контрольные вопросы:**
1. Чем `HierarchyConfiguration` принципиально отличается от `SubnamespaceAnchor` (где живет каждый и какую задачу решает)?
2. Какие ресурсы HNC распространяет по умолчанию, и как изменить этот список?
3. Почему механизм `SubnamespaceAnchor` элегантно решает проблему "командам нельзя давать кластерное право create namespace"?
4. Что произойдет, если пользователь попробует отредактировать скопированный Secret напрямую в дочернем namespace? (Подсказка: HNC reconciliation loop).

---

## Часть 3: Виртуальные кластеры (vcluster)

### Теория для изучения перед частью

Если HNC — это развитие Soft Multi-tenancy, то **vcluster (Virtual Cluster)** — это переход к Hard Multi-tenancy без затрат на поднятие физического кластера. Это буквально «Kubernetes внутри Kubernetes».

В одном StatefulSet хост-кластера работают компоненты управления тенанта (k3s, k0s, или чистый k8s):

```text
Host-кластер (например, ваш стенд Kubespray, ns lab)
┌───────────────────────────────────────────────────────────────────┐
│  StatefulSet my-vcluster-0                                        │
│  ┌───────────────────────────────┐     PVC data (SQLite/kine)     │
│  │ kube-apiserver + controllers  │◄─── состояние ВИРТУАЛЬНОГО     │
│  │ (СВОЙ API-мир, свои CRD)      │     кластера тенанта           │
│  │ syncer ───────────────────────┼───► создаёт «теневые» поды     │
│  └───────────────────────────────┘     в хост-namespace lab       │
│                                                                   │
│  nginx-x-default-x-my-vcluster   ◄──── физическая тень пода       │
│                                        тенанта                    │
└───────────────────────────────────────────────────────────────────┘
```

- У тенанта внутри vcluster есть полные права **cluster-admin**: он может создавать свои ns, ставить свои CRD, настраивать свой RBAC. Хостовый кластер этого вообще не видит, так как это всё хранится в SQLite внутри пода vcluster.
- Своих НОД у vcluster нет (хотя API-сервер vcluster показывает псевдо-ноды). **Syncer** — ключевой компонент vcluster, который перехватывает попытки создать поды внутри виртуального кластера и транслирует (синхронизирует) их в хостовый namespace. 
- Имена подов при трансляции преобразуются: `<имя_пода>-x-<виртуальный_ns>-x-<имя_vcluster>`.
- **Следствие**: Любые ограничения хост-кластера (ResourceQuota, LimitRange, PSA, NetworkPolicy) наложенные на хостовый namespace, ПРОДОЛЖАЮТ действовать на тенанта! Это железный контракт платформы.

> ⚙️ **Грабли стенда (reality):** В этой лабе используется vendored-манифест с vcluster **0.34.2**. Версия 0.19, с которой модуль начинался, на k8s 1.33+ НЕ работает: новый аллокатор ClusterIP изменил текст ошибки автоопределения service-CIDR. Syncer не мог создать ни одного сервиса. Подробности можно найти в комментариях внутри `manifests/01-vcluster.yaml`.

### 3.1 Архитектура Syncer-паттерна

Syncer выполняет низкоуровневую синхронизацию (Low-level sync). Он не запускает kubelet. Вместо этого он смотрит на ресурсы, создаваемые в vcluster API (Pods, Services, Ingress, PersistentVolumeClaims), "переводит" их спецификации и создает в хостовом кластере. Когда хостовый kubelet запускает под, Syncer читает его статус с хоста и записывает обратно в vcluster API, создавая иллюзию полного контроля у тенанта.

### 3.2 Доступ внутрь и первый под

Извлечем конфигурацию для доступа к виртуальному кластеру и поднимем port-forward (vcluster не имеет внешнего Ingress по умолчанию для безопасности).

```bash
# Извлекаем kubeconfig vcluster и заменяем адрес сервера на локальный порт
kubectl get secret vc-my-vcluster -n lab -o jsonpath='{.data.config}' | base64 -d \
  | sed 's|server: https://.*|server: https://localhost:18443|' > vcluster.yaml

# Пробрасываем порт
kubectl -n lab port-forward svc/my-vcluster 18443:443 &

# Тестируем подключение! Мы стучимся в API виртуального кластера
kubectl --kubeconfig vcluster.yaml get namespaces
```

Ожидаемый вывод:
```text
NAME              STATUS   AGE
kube-system       Active   52s
kube-public       Active   52s
kube-node-lease   Active   52s
default           Active   52s
```
Как видите, внутри — чистый кластер! Namespace `lab` здесь нет.

Создадим под внутри vcluster:
```bash
kubectl --kubeconfig vcluster.yaml run nginx --image=nginx:1.27-alpine
sleep 15
kubectl --kubeconfig vcluster.yaml get pod nginx -o wide
# Внутри vcluster под выглядит обычно, но столбец NODE показывает фейковое или прокинутое имя:
# NAME    READY   STATUS    ...   NODE
# nginx   1/1     Running   ...   k8s-w-1
```

### 3.3 Синхронизация Ingress и сервисов

А теперь посмотрим на хостовый кластер. Тенант уверен, что он один, но администратор видит реальную картину:

```bash
kubectl -n lab get pods
```
Ожидаемый вывод:
```text
NAME                                                  READY   STATUS
coredns-d786d7997-fx4fp-x-kube-system-x-my-vcluster   1/1     Running
my-vcluster-0                                         1/1     Running
nginx-x-default-x-my-vcluster                         1/1     Running
```

Обратите внимание, что CoreDNS виртуального кластера тоже запущен как обычный под в хостовом кластере!

Если тенант создаст Service типа ClusterIP, он будет синхронизирован в хост-кластер, чтобы поды могли маршрутизировать трафик через хостовый kube-proxy.

### 3.4 Host-квота против тенанта

Мы подошли к ключевому моменту изоляции. Проверим бухгалтерский учет хостового namespace:

```bash
kubectl -n lab describe quota lab-quota
```
Ожидаемый вывод:
```text
Resource         Used   Hard
--------         ----   ----
limits.cpu       1200m  2      <- vcluster pod (1) + его coredns (200m)
requests.cpu     320m   1
requests.memory  704Mi  1Gi
```

Каждый "теневой" под тенанта добавляется к потреблению хостовой квоты. Если тенант внутри vcluster попытается запросить ресурсы, превышающие остаток хостовой квоты, под в vcluster навсегда останется в статусе `Pending`!

Для администратора vcluster (тенанта) это выглядит загадочно — планировщик vcluster не видит проблем, но под не запускается. Причину покажет только событие Syncer'а:

```bash
# Внутри vcluster:
kubectl --kubeconfig vcluster.yaml get events
```
Реальное событие с кластера:
```text
Warning  SyncError  pod/greedy-app
  Error syncing to host cluster: create object:
  pods "greedy-app-x-default-x-my-vcluster" is forbidden:
  exceeded quota: lab-quota, requested: limits.cpu=1500m,
  used: limits.cpu=1500m, limited: limits.cpu=2
```
Этот инцидент разобран в директории `broken/scenario-01/`.

**Контрольные вопросы:**
1. Где физически исполняется под, созданный внутри vcluster?
2. Почему событие об отказе из-за квоты — это `SyncError`, а не стандартный `FailedScheduling`?
3. Можете ли вы, будучи администратором vcluster, обойти NetworkPolicy, установленную администратором хостового кластера на namespace `lab`?
4. Как vcluster обрабатывает создание CRD тенантом? Появляются ли они в хостовом кластере?

---

## Часть 4: Стоимость namespace (FinOps)

### Теория для изучения перед частью

Cloud Native FinOps в Kubernetes имеет свою специфику. Платформенная команда платит облачному провайдеру (или железу) за **НОДЫ** целиком. Но тенанты потребляют ресурсы **бронью (requests)**. 

Забронированное тенантом ядро, даже если оно простаивает на 99%, планировщик (kube-scheduler) уже не может отдать другой команде. Именно поэтому chargeback (внутренний биллинг) в Enterprise всегда рассчитывается от *requests*, а не от *usage* (фактического использования).

### 4.1 Философия аллокации расходов в Kubernetes

- **Showback** — демонстрация команде стоимости ее инфраструктуры в деньгах, без реального списания из бюджета (для мотивации).
- **Chargeback** — реальное финансовое списание во внутреннем биллинге организации.
- **Idle Cost (Налог на простой)** — стоимость ресурсов, которые забронированы через requests, но фактически не используются.

Прайс нашего стенда (эмулируем GCP `e2-medium`): нода ≈ **$0.0335/час** (2 vCPU + 4 GB).
Обычно стоимость ноды раскладывают по весам: ~2/3 за CPU и ~1/3 за RAM.
- **1 vCPU·час ≈ $0.0112**
- **1 GiB·час ≈ $0.0028**

Промышленные инструменты, такие как **OpenCost** (проект CNCF) или Kubecost, автоматизируют этот процесс, интегрируясь с API облачного провайдера. Механика, которую мы сделаем ниже руками через PromQL, абсолютно идентична логике движка OpenCost.

> ⚠️ **Reality-находка:** OpenCost версии 1.117 на нодах GCE жестко автоопределяет провайдера и требует ключ Billing API еще до чтения кастомного прайса. На учебном стенде он упадет с `panic: Supply a GCP Key`. Поэтому мы будем использовать сырые PromQL запросы к `kube-prometheus-stack` — это даст более глубокое понимание механики под капотом.

### 4.2 Стоимость по namespace (showback)

Для работы с PromQL откроем проброс портов до Prometheus:

```bash
kubectl -n monitoring port-forward svc/kps-kube-prometheus-stack-prometheus 19090:9090 &
```

Откройте UI Prometheus: http://localhost:19090

Запрос для получения суммарной брони CPU по каждому namespace:
```promql
sum by (namespace) (kube_pod_container_resource_requests{resource="cpu", unit="core"})
```

Реальный срез со стенда:
```text
kube-system            1.700 CPU requests
lab                    0.320 CPU requests
envoy-gateway-system   0.210 CPU requests
hnc-system             0.100 CPU requests
```

Теперь самое интересное — перевод брони в реальные деньги одним составным запросом. Мы умножаем запросы на стоимость CPU и RAM:

```promql
  sum by (namespace) (kube_pod_container_resource_requests{resource="cpu", unit="core"}) * 0.0112
+ sum by (namespace) (kube_pod_container_resource_requests{resource="memory", unit="byte"}) / 2^30 * 0.0028
```

Для namespace `lab` результат: 0.32 CPU × $0.0112 + 0.69 GiB × $0.0028 ≈ **$0.0055/час ≈ $4/месяц**.
Именно столько в реальных деньгах стоит наш тестовый vcluster-тенант.

### 4.3 Overprovisioning (rightsizing) и Idle-налог

Команды часто просят "с запасом". Выявим этот запас. Запрос фактического потребления CPU:

```promql
sum by (namespace) (rate(container_cpu_usage_seconds_total{container!=""}[10m]))
```

Факты со стенда: namespace `lab` реально потребляет **~0.075 ядра при забронированных 0.32**. Утилизация составляет всего ~23%. 
Остальные 77% брони — это оплаченный, но простаивающий простой, который обходится компании в деньги.

Лечение простое (Rightsizing):
1. Ручная корректировка `requests` по фактическому p95.
2. Внедрение Vertical Pod Autoscaler (VPA, см. модуль 11).

**Контрольные вопросы:**
1. Почему внутренний биллинг команд всегда считают от `requests`, а не от `usage`?
2. В чем разница между моделями Showback и Chargeback в Enterprise?
3. У namespace `team-data` утилизация CPU составляет 15% на протяжении месяца. Какие два пути исправления ситуации существуют и в чем риски каждого из них?

---

## Часть 5: Troubleshooting (Комплексные сценарии)

Multi-tenancy системы сложны в отладке. Ниже разобраны реальные боевые сценарии отказов.

### Сценарий 5.1: Каскадный отказ создания namespace из-за падения HNC webhook
**Контекст**: Вы внедрили HNC в кластере на 500 нод. Внезапно все пайплайны CI/CD падают с ошибкой создания namespace.
**Симптомы**: 
Команда выполняет `kubectl create ns test-123` и получает:
`Error from server (InternalError): Internal error occurred: failed calling webhook "namespaces.hnc.x-k8s.io": Post "https://hnc-webhook-service.hnc-system.svc:443...": dial tcp 10.96.x.x:443: connect: connection refused`
**Диагностика**:
Вебхук HNC перехватывает ВСЕ запросы на создание namespace для валидации иерархии. Если поды HNC-контроллера упали (OOMKilled или выселены с ноды), API сервер k8s не может достучаться до вебхука и, согласно настройке `failurePolicy: Fail`, блокирует операцию.
**Решение**:
1. Экстренное восстановление пайплайнов: `kubectl delete validatingwebhookconfiguration hnc-validating-webhook-configuration` (это снимет валидацию, пока HNC не починят).
2. Расследование падения HNC: `kubectl get pods -n hnc-system` (вероятно, потребуется поднять `limits.memory`).

### Сценарий 5.2: vcluster Syncer отклоняет поды из-за Mutating Webhooks хоста
**Контекст**: Тенант жалуется, что поды в его vcluster создаются, но в статусе написано `SyncError`, а под не стартует.
**Симптомы**:
`kubectl --kubeconfig vc.yaml get events` показывает:
`Error syncing to host cluster: pods "app-x-ns-x-vc" is forbidden: pods with sidecar "linkerd-proxy" are not allowed by policy`.
**Диагностика**:
На хостовом кластере установлен Service Mesh (Istio/Linkerd) или система политик (Kyverno), которая автоматически инжектит сайдкары или мутирует поды в хостовом namespace. Syncer vcluster'а пытается создать "чистый" под из vcluster'а, но хостовый API мутирует его. Syncer видит, что спецификация пода на хосте не совпадает со спецификацией в vcluster, и падает в цикл конфликтов (Conflict error) или отклоняется политикой.
**Решение**:
Отключить инжекцию хостовых сайдкаров для namespace виртуального кластера. Например:
`kubectl label ns lab linkerd.io/inject=disabled` или настроить исключения в Kyverno.

### Сценарий 5.3: CoreDNS внутри vcluster не резолвит внешние ресурсы
**Контекст**: Тенант поднял внутри vcluster приложение, которое пытается достучаться до API внешней базы данных (по доменному имени), но получает `NXDOMAIN`. При этом внешние пинги по IP работают.
**Симптомы**:
Логи пода внутри vcluster: `curl: (6) Could not resolve host: api.external-service.com`.
**Диагностика**:
CoreDNS, запущенный внутри vcluster, настроен так, чтобы резолвить только сервисы ВНУТРИ виртуального кластера (виртуальные `*.svc.cluster.local`). По умолчанию он перенаправляет (forward) неизвестные запросы на DNS-серверы хостовой ноды, например `169.254.169.254`, что может быть заблокировано NetworkPolicy на хосте.
**Решение**:
Проверить конфигурацию CoreDNS в vcluster и убедиться, что секция `forward . /etc/resolv.conf` (или DNS хост-кластера) корректна, а хостовый namespace (`lab`) имеет NetworkPolicy, разрешающую исходящий UDP трафик на порт 53.

### Сценарий 5.4: FinOps метрики показывают нули для Init-контейнеров
**Контекст**: Платформенная команда настроила биллинг по PromQL `kube_pod_container_resource_requests`, но в конце месяца счета оказались сильно занижены.
**Симптомы**:
Приложения тенанта используют "тяжелые" Init-контейнеры для миграции БД (запрашивают по 4 CPU), но в биллинг они не попадают.
**Диагностика**:
Запрос `sum(kube_pod_container_resource_requests)` агрегирует все контейнеры пода. Однако в Kubernetes ресурсы, необходимые поду для старта, рассчитываются как `max(sum(app_containers), max(init_containers))`. Простой `sum` не учитывает специфику шедулера k8s для Init-контейнеров.
**Решение**:
Для точного биллинга необходимо использовать метрики `kube_pod_resource_requests` (суммарный request пода), а не складывать метрики отдельных контейнеров `kube_pod_container_resource_requests`.

### Краткая таблица частых ошибок

| Симптом | Причина | Диагностика / фикс |
|---------|---------|--------------------|
| Под в vcluster вечно `Pending`, в host его нет | host-квота/политика отвергла «тень» | `kubectl --kubeconfig vc.yaml get events` → `SyncError`; вписаться в квоту. |
| `kubectl --kubeconfig vcluster.yaml` — connection refused | port-forward умер / STS не Ready | перезапустить port-forward; `kubectl -n lab rollout status sts/my-vcluster`. |
| Сервисы внутри vcluster не получают ClusterIP | service-CIDR vcluster ≠ CIDR хоста | логи syncer: `not in the valid range`; использовать vcluster ≥0.2x. |
| RoleBinding не приехал в дочерний ns | иерархия не установилась | `kubectl get ns <child> --show-labels`; проверить аннотации. |
| Не удаляется ns субнеймспейса | удалять надо якорь, а не ns | `kubectl delete subns <name> -n <parent>`. |

---

## Практические задания (отработка)

1. **Многоуровневая иерархия**: Постройте дерево namespace'ов `org → team-a → team-a-dev/team-a-prod` с использованием `SubnamespaceAnchor`. Выдайте `RoleBinding` на уровне `org` и с помощью `kubectl get rolebinding` докажите, что права прозрачно приехали на все четыре уровня.
2. **Распространение NetworkPolicy**: С помощью `HNCConfiguration` включите распространение ресурса `networkpolicies` (apiGroup: `networking.k8s.io`). Создайте строгую политику Deny-All в корневом namespace и убедитесь, что все дочерние namespace автоматически стали изолированы.
3. **Развертывание CRD в vcluster**: Подключитесь к vcluster. Установите любой Custom Resource Definition (например, CertificateCRD из cert-manager). Затем переключитесь на хостовый кластер и докажите (`kubectl get crd`), что этого CRD там нет. Это демонстрация Hard Control Plane Isolation.
4. **Ограничения Data Plane**: Воспроизведите инцидент из папки `broken/scenario-01/`. Тенант пытается запустить "жадный" под. Найдите причину через `SyncError`, почините проблему двумя разными способами:
   - Как тенант: уменьшив requests в манифесте пода.
   - Как платформенный инженер: расширив `ResourceQuota` в namespace `lab`.
   *(Не забудьте вернуть квоту назад после эксперимента!)*
5. **Финансовая аналитика**: Используя PromQL, найдите ТОП-3 самых дорогих namespace в вашем кластере на данный момент (по requests CPU).
6. **Выявление мусора**: Напишите PromQL запрос, который покажет объем "выброшенных на ветер" ресурсов (разница между суммарными requests CPU и фактическим rate потребления CPU). В каком namespace компания теряет больше всего денег на простаивающих мощностях?

---

## Проверка модуля

Для валидации корректности выполнения базовых заданий предусмотрены автоматические скрипты проверки:

```bash
bash verify/verify.sh
# Ожидаемый вывод:
# [OK] HNC: иерархия работает, RBAC распространяется parent -> child
# [OK] vcluster: API доступен
# [OK] vcluster: под из виртуального кластера реально работает в host (syncer)
# [OK] module 28 verified
```

Уборка ресурсов:

```bash
bash verify/cleanup.sh
```

---

## Шпаргалка

```bash
# --- HNC ---
# Вложить существующий namespace CHILD в родительский PARENT
kubectl apply -f - <<'Y'
apiVersion: hnc.x-k8s.io/v1alpha2
kind: HierarchyConfiguration
metadata: {name: hierarchy, namespace: CHILD}
spec: {parent: PARENT}
Y

kubectl get subns -n PARENT                    # Список якорей (созданных субнеймспейсов)
kubectl get ns CHILD --show-labels             # Проверка дерева: наличие меток *.tree.hnc.x-k8s.io/depth
kubectl delete subns NAME -n PARENT            # Правильное удаление субнеймспейса (удаляем якорь)

# --- vcluster ---
# Подготовка kubeconfig
kubectl get secret vc-my-vcluster -n lab -o jsonpath='{.data.config}' | base64 -d > vc.yaml
kubectl -n lab port-forward svc/my-vcluster 18443:443 &

# Работа тенанта
kubectl --kubeconfig vc.yaml get ns            # Просмотр мира тенанта

# Взгляд администратора платформы
kubectl -n lab get pods                        # Тени подов: <pod>-x-<ns>-x-<vcluster>

# --- FinOps ---
# Стоимость ns, $/час (1 vCPU·ч=$0.0112, 1 GiB·ч=$0.0028 — базовый прайс стенда)
sum by (namespace) (kube_pod_container_resource_requests{resource="cpu",unit="core"}) * 0.0112
  + sum by (namespace) (kube_pod_container_resource_requests{resource="memory",unit="byte"}) / 2^30 * 0.0028

# Фактическое потребление CPU (утилизация) для выявления Idle-налога
sum by (namespace) (rate(container_cpu_usage_seconds_total{container!=""}[10m]))
```

---

## Финальная карта ресурсов модуля

| Ресурс | Где | Назначение |
|--------|-----|------------|
| `manifests/01-vcluster.yaml` | ns `lab` | vcluster 0.34.2 (vendored helm-рендер, критично использовать эту версию) |
| `helm-values.yaml` | репо | Исходные values для перегенерации рендера vcluster |
| `manifests/02-hnc.yaml` | ns `hnc-system` | HNC v1.1.0 (vendored манифест контроллера) |
| `broken/scenario-01/` | vcluster | инцидент: host-квота блокирует теневой под тенанта |
| `solutions/01-host-quota/` | ns `lab` | решение: исправление манифеста или расширение квоты |
| `tasks/01..03` | — | Задания для HNC, vcluster, FinOps-PromQL |
| `verify/{prepare,verify,cleanup}.sh` | — | QA-контракт модуля и автотесты |
