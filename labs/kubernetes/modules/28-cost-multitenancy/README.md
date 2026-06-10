# Лабораторная работа 28: Multi-tenancy и стоимость — HNC, vcluster и FinOps

## Оглавление
<!-- TOC -->
- [Цели](#)
- [Предварительные требования](#-)
- [Стартовая проверка](#-)
- [Часть 1: Спектр изоляции тенантов](#-1---)
  - [Теория для изучения перед частью](#----)
- [Часть 2: Иерархические namespace (HNC)](#-2--namespace-hnc)
  - [Теория для изучения перед частью](#----)
  - [2.1 Иерархия и наследование RBAC](#21----rbac)
  - [2.2 Субнеймспейсы через якорь](#22---)
  - [2.3 Защита от выстрела в ногу](#23-----)
- [Часть 3: Виртуальные кластеры (vcluster)](#-3---vcluster)
  - [Теория для изучения перед частью](#----)
  - [3.1 Доступ внутрь и первый под](#31-----)
  - [3.2 Host-квота против тенанта](#32-host---)
- [Часть 4: Стоимость namespace (FinOps)](#-4--namespace-finops)
  - [Теория для изучения перед частью](#----)
  - [4.1 Стоимость по namespace (showback)](#41---namespace-showback)
  - [4.2 Overprovisioning (rightsizing)](#42-overprovisioning-rightsizing)
- [Часть 5: Troubleshooting](#-5-troubleshooting)
- [Практические задания (отработка)](#--)
- [Проверка модуля](#-)
- [Шпаргалка](#)
- [Финальная карта ресурсов модуля](#---)
<!-- /TOC -->


⏱ время: 90–120 мин · 🎚 сложность: продвинутая · ⚙️ пререквизиты: модули 06 (квоты/LimitRange), 07 (RBAC), 12 (resource management), 17 (Prometheus)

## Цели

1. Понять спектр изоляции тенантов: от общего namespace до выделенного кластера.
2. Управлять ДЕРЕВОМ namespace'ов через HNC: наследование RBAC, субнеймспейсы.
3. Поднять виртуальный кластер (vcluster): свой API-сервер тенанта внутри одного namespace.
4. Увидеть на практике, что hard multi-tenancy НЕ отменяет host-контракты (квоты).
5. Посчитать стоимость каждого namespace по requests (showback) и найти overprovisioning.

## Предварительные требования

```bash
export KUBECONFIG=/root/.kube/kubespray.conf   # наш стенд; на другом кластере — свой путь

# В lab должны действовать стандартные квоты стенда:
kubectl -n lab get quota lab-quota || bash ../../scripts/bootstrap/01-apply-quotas.sh

# Применяем компоненты модуля (HNC v1.1.0 + vcluster 0.34.2, всё vendored):
kubectl apply -f manifests/
kubectl -n hnc-system rollout status deploy/hnc-controller-manager --timeout=180s
kubectl -n lab rollout status sts/my-vcluster --timeout=300s
```

## Стартовая проверка

```bash
kubectl get ns hnc-system && kubectl -n lab get sts my-vcluster
# NAME          READY   AGE
# my-vcluster   1/1     2m
```

---

## Часть 1: Спектр изоляции тенантов

### Теория для изучения перед частью

Когда один кластер делят несколько команд (тенантов), выбирают компромисс
между изоляцией и стоимостью:

```
слабее изоляция ◄──────────────────────────────────────────► сильнее
дешевле        ◄──────────────────────────────────────────► дороже

общий ns      ns на тенанта        иерархия ns        vcluster          отдельный
(метки/RBAC)  + quota/netpol/PSA   (HNC)              (свой API-сервер) кластер
   m01-07        Project E          Часть 2            Часть 3          (вне курса)
```

| Подход | Что своё у тенанта | Что общее | Когда уместен |
|--------|--------------------|-----------|---------------|
| Namespace + RBAC/quota/netpol (**soft**) | объекты в ns | API-сервер, CRD, версия k8s, ноды | команды одной организации, доверие среднее |
| Иерархия ns (HNC) | поддерево ns | то же, что выше | много команд/сред, RBAC «сверху вниз» |
| vcluster (**hard**) | СВОЙ API-сервер, СВОИ CRD, свой RBAC-мир | ноды, kubelet, ядро, сеть | тенанту нужен cluster-admin (CRD, операторы), платформа отдаёт «кластер напрокат» |
| Отдельный кластер | всё | ничего | регуляторика, blast radius, прод разных продуктов |

Ключевая мысль: **изоляция API ≠ изоляция ресурсов**. Даже у vcluster поды
физически работают в host-namespace и подчиняются его ResourceQuota/PSA —
проверим это руками в Части 3.

**Контрольные вопросы:**
1. Чем soft multi-tenancy принципиально ограничен в отношении CRD?
2. Почему «ns на тенанта» дешевле vcluster, а vcluster дешевле кластера на тенанта?
3. Какой общий компонент остаётся у ВСЕХ вариантов, кроме отдельного кластера?

---

## Часть 2: Иерархические namespace (HNC)

### Теория для изучения перед частью

HNC (Hierarchical Namespace Controller) добавляет namespace'ам отношения
«родитель → ребёнок»:

- **Propagation:** объекты родителя (по умолчанию Role и RoleBinding)
  автоматически копируются во все дочерние ns и поддерживаются в актуальном
  состоянии. Выдали команде права на корневой ns — они есть во всех её средах.
- **HierarchyConfiguration** — singleton-объект `hierarchy` В ДОЧЕРНЕМ ns со
  `spec.parent`: так вкладывают УЖЕ существующий namespace.
- **SubnamespaceAnchor** — «якорь» В РОДИТЕЛЬСКОМ ns: HNC сам создаёт
  одноимённый дочерний namespace (способ давать командам право заводить себе
  среды БЕЗ cluster-уровневого права создавать ns).
- Дерево видно по меткам ns: `<родитель>.tree.hnc.x-k8s.io/depth`.

> ⚠️ Аннотацию `hnc.x-k8s.io/subnamespace-of` руками не ставят: её
> поддерживает контроллер для созданных через якорь субнеймспейсов, иерархию
> она НЕ задаёт.

> 📦 Проект HNC переехал в архив (`kubernetes-retired`) — концепция иерархии
> и propagation остаётся отличной учебной моделью, но для нового прода
> смотрите на Capsule или на vcluster (Часть 3). Манифест v1.1.0 vendored в
> `manifests/02-hnc.yaml` — работает на 1.36 без нареканий.

### 2.1 Иерархия и наследование RBAC

```bash
kubectl create ns parent-ns
kubectl create ns child-ns

kubectl apply -f - <<'YAML'
apiVersion: hnc.x-k8s.io/v1alpha2
kind: HierarchyConfiguration
metadata:
  name: hierarchy
  namespace: child-ns
spec:
  parent: parent-ns
YAML

kubectl create rolebinding team-edit -n parent-ns --clusterrole=edit --user=dev-lead
sleep 5
kubectl get rolebinding -n child-ns
```

Ожидаемый вывод (снято с этого кластера):

```
NAME        ROLE               AGE
team-edit   ClusterRole/edit   9s
```

RoleBinding создавали ТОЛЬКО в parent-ns — в child-ns его принёс HNC. Дерево
видно по меткам:

```bash
kubectl get ns child-ns -o jsonpath='{.metadata.labels}'
# {"child-ns.tree.hnc.x-k8s.io/depth":"0", ...,"parent-ns.tree.hnc.x-k8s.io/depth":"1"}
```

### 2.2 Субнеймспейсы через якорь

```bash
kubectl apply -f - <<'YAML'
apiVersion: hnc.x-k8s.io/v1alpha2
kind: SubnamespaceAnchor
metadata:
  name: team-a-dev
  namespace: parent-ns
YAML
sleep 5

# HNC сам создал ns и проставил служебную аннотацию:
kubectl get ns team-a-dev -o jsonpath='{.metadata.annotations.hnc\.x-k8s\.io/subnamespace-of}{"\n"}'
# parent-ns

# и RBAC родителя уже там:
kubectl get rolebinding team-edit -n team-a-dev
# team-edit   ClusterRole/edit   7s
```

### 2.3 Защита от выстрела в ногу

Вебхук HNC валидирует иерархию НА ВХОДЕ — задать несуществующего родителя
нельзя (снято с этого кластера):

```
Error from server (Forbidden): ... admission webhook
"hierarchyconfigurations.hnc.x-k8s.io" denied the request:
... "hierarchy" is forbidden: requested parent "team-prod" does not exist
```

**Контрольные вопросы:**
1. Чем HierarchyConfiguration отличается от SubnamespaceAnchor (где живёт каждый и что делает)?
2. Какие объекты HNC распространяет по умолчанию и зачем именно их?
3. Почему субнеймспейсы решают проблему «команды нельзя давать право create namespace»?

---

## Часть 3: Виртуальные кластеры (vcluster)

### Теория для изучения перед частью

vcluster — «Kubernetes внутри Kubernetes». В одном StatefulSet host-кластера
работают:

```
host-кластер (Kubespray, ns lab)
┌──────────────────────────────────────────────────────────────┐
│  StatefulSet my-vcluster-0                                   │
│  ┌──────────────────────────────┐   PVC data (SQLite/kine)   │
│  │ kube-apiserver + контроллеры │◄── состояние ВИРТУАЛЬНОГО  │
│  │ (дистро k8s, СВОЙ API-мир)   │    кластера                │
│  │ syncer ──────────────────────┼──► создаёт «теневые» поды  │
│  └──────────────────────────────┘    в host-ns lab           │
│  nginx-x-default-x-my-vcluster  ◄─── тень пода тенанта       │
└──────────────────────────────────────────────────────────────┘
```

- У тенанта внутри — полный cluster-admin: свои ns, CRD, RBAC. Host этого
  не видит и не страдает.
- Своих НОД у vcluster нет: syncer транслирует поды в host-namespace с
  именами `<pod>-x-<vns>-x-<vcluster>`; там их планирует обычный host-scheduler.
- Следствие: ResourceQuota/LimitRange/PSA/NetworkPolicy host-namespace
  ПРОДОЛЖАЮТ действовать на тенанта — это контракт платформы.

> ⚙️ **Грабли стенда (reality):** манифест vendored с vcluster **0.34.2**.
> Версия 0.19, с которой модуль начинался, на k8s 1.33+ НЕ работает: новый
> аллокатор ClusterIP (MultiCIDRServiceAllocator) изменил текст ошибки, по
> которому 0.19 автоопределял service-CIDR → CIDR падал в дефолт 10.96.0.0/12
> (у Kubespray — 10.233.0.0/18) → syncer не мог создать ни одного сервиса.
> Подробности — в шапке `manifests/01-vcluster.yaml`.

### 3.1 Доступ внутрь и первый под

```bash
kubectl get secret vc-my-vcluster -n lab -o jsonpath='{.data.config}' | base64 -d \
  | sed 's|server: https://.*|server: https://localhost:18443|' > vcluster.yaml
kubectl -n lab port-forward svc/my-vcluster 18443:443 &

kubectl --kubeconfig vcluster.yaml get namespaces
# NAME              STATUS   AGE
# kube-system       Active   52s
# kube-public       Active   52s
# kube-node-lease   Active   52s
# default           Active   52s

kubectl --kubeconfig vcluster.yaml run nginx --image=nginx:1.27-alpine
sleep 15
kubectl --kubeconfig vcluster.yaml get pod nginx -o wide
# NAME    READY   STATUS    ...   NODE
# nginx   1/1     Running   ...   k8s-w-1     <- имя РЕАЛЬНОЙ ноды host-кластера
```

А теперь то же самое глазами host-кластера:

```bash
kubectl -n lab get pods
# NAME                                                  READY   STATUS
# coredns-d786d7997-fx4fp-x-kube-system-x-my-vcluster   1/1     Running
# my-vcluster-0                                         1/1     Running
# nginx-x-default-x-my-vcluster                         1/1     Running
```

Внутри тенант видит «обычный кластер», снаружи это просто поды в ns `lab`
с транслированными именами (включая CoreDNS самого vcluster).

### 3.2 Host-квота против тенанта

Посмотрите бухгалтерию host-namespace:

```bash
kubectl -n lab describe quota lab-quota
# limits.cpu       1200m  2      <- vcluster (1) + его coredns (200m)
# requests.cpu     320m   1
# requests.memory  704Mi  1Gi
```

Каждый под тенанта добавляется к used. Если тенант запросит больше остатка,
под внутри vcluster останется `Pending` навсегда, а причину покажет только
событие syncer'а — этот инцидент оформлен как **`broken/scenario-01/`**
(симптом, диагностика, решение). Реальное событие с этого кластера:

```
Warning  SyncError  pod/greedy-app
  Error syncing to host cluster: create object:
  pods "greedy-app-x-default-x-my-vcluster" is forbidden:
  exceeded quota: lab-quota, requested: limits.cpu=1500m,
  used: limits.cpu=1500m, limited: limits.cpu=2
```

**Контрольные вопросы:**
1. Где физически исполняется под, созданный внутри vcluster?
2. Почему событие об отказе — `SyncError`, а не `FailedScheduling`?
3. Какие механизмы host-кластера продолжают ограничивать тенанта vcluster?

---

## Часть 4: Стоимость namespace (FinOps)

### Теория для изучения перед частью

Платформа платит за НОДЫ, а тенанты потребляют их **бронью** (requests):
забронированное, но неиспользуемое ядро нельзя отдать другому — поэтому
showback/chargeback считают от requests, а не от usage.

- **Showback** — показать команде её стоимость; **chargeback** — реально
  списать во внутреннем биллинге.
- Прайс стенда: e2-medium us-central1 ≈ **$0.0335/час** (2 vCPU + 4 GB) →
  раскладываем ~2/3 на CPU и ~1/3 на RAM:
  **1 vCPU·час ≈ $0.0112; 1 GiB·час ≈ $0.0028**. Кластер из 3 нод ≈ $73/мес.
- Промышленные инструменты — **OpenCost** (CNCF) / Kubecost: тот же расчёт
  (requests × прайс из cloud-биллинга) + хранение истории и API. Механику
  ниже делаем руками на PromQL — она одна и та же.

> ⚠️ **Reality-находка:** OpenCost 1.117 на нодах GCE жёстко выбирает
> GCP-провайдера (по `providerID`/metadata) и требует ключ Billing API ещё до
> чтения кастомного прайса — на учебном стенде без биллинг-ключа он не
> стартует (`panic: Supply a GCP Key`). Поэтому практика ниже — на PromQL по
> kube-prometheus-stack; концепции OpenCost она покрывает полностью.

### 4.1 Стоимость по namespace (showback)

```bash
kubectl -n monitoring port-forward svc/kps-kube-prometheus-stack-prometheus 19090:9090 &
```

PromQL (UI: http://localhost:19090):

```promql
sum by (namespace) (kube_pod_container_resource_requests{resource="cpu", unit="core"})
```

Реальный срез этого стенда:

```
kube-system            1.700 CPU requests      lab          0.320
envoy-gateway-system   0.210                   hnc-system   0.100
```

Перевод в деньги одним запросом:

```promql
  sum by (namespace) (kube_pod_container_resource_requests{resource="cpu", unit="core"}) * 0.0112
+ sum by (namespace) (kube_pod_container_resource_requests{resource="memory", unit="byte"}) / 2^30 * 0.0028
```

Для `lab`: 0.32 CPU × $0.0112 + 0.69 GiB × $0.0028 ≈ **$0.0055/час ≈ $4/мес** —
вот цена нашего vcluster-тенанта.

### 4.2 Overprovisioning (rightsizing)

```promql
sum by (namespace) (rate(container_cpu_usage_seconds_total{container!=""}[10m]))
```

Реальный факт стенда: `lab` потребляет **~0.075 ядра при брони 0.32** —
утилизация ~23%. Остальные 77% брони — оплаченный простой. Лечение:
скорректировать requests по фактическому p95 (модуль 08) или отдать VPA
(модуль 11). Это самый быстрый способ экономии в любом кластере.

**Контрольные вопросы:**
1. Почему биллинг тенантов считают от requests, а не от фактического usage?
2. Чем showback отличается от chargeback?
3. У namespace утилизация CPU 20% — какие два пути исправления и какой риск у каждого?

---

## Часть 5: Troubleshooting

| Симптом | Причина | Диагностика / фикс |
|---------|---------|--------------------|
| Под в vcluster вечно `Pending`, в host его нет | host-квота/политика отвергла «тень» | `kubectl --kubeconfig vcluster.yaml get events` → `SyncError`; вписаться в квоту (`broken/scenario-01`) |
| `kubectl --kubeconfig vcluster.yaml` — connection refused | port-forward умер / STS не Ready | перезапустить port-forward; `kubectl -n lab rollout status sts/my-vcluster` |
| Сервисы внутри vcluster не получают ClusterIP | service-CIDR vcluster ≠ CIDR хоста (старые версии) | логи syncer: `not in the valid range`; vcluster ≥0.2x (см. шапку манифеста) |
| HierarchyConfiguration отвергается вебхуком | родитель не существует / цикл | `requested parent ... does not exist`; создать родителя заранее |
| RoleBinding не приехал в дочерний ns | иерархия не установилась | `kubectl get ns <child> --show-labels` → есть ли `<parent>.tree...depth`; `kubectl -n <child> get hierarchyconfiguration hierarchy -o yaml` |
| Не удаляется ns субнеймспейса | удалять надо якорь, а не ns | `kubectl delete subns <name> -n <parent>` |

---

## Практические задания (отработка)

1. Постройте дерево `org → team-a → team-a-dev/team-a-prod` (anchor'ы),
   выдайте RoleBinding на `org` и докажите, что он есть на всех четырёх уровнях.
2. Создайте Secret в parent-ns и убедитесь, что по умолчанию он НЕ
   распространяется (propagation касается Role/RoleBinding); найдите в
   `kubectl get hncconfiguration config -o yaml`, как добавить тип.
3. Внутри vcluster установите любой CRD (например, из модуля 19) и покажите,
   что в host-кластере его НЕТ (`kubectl get crd | grep ...`).
4. Воспроизведите `broken/scenario-01` и почините его двумя способами:
   правкой пода и расширением host-квоты (верните квоту назад!).
5. Посчитайте PromQL'ем стоимость namespace `monitoring` в $/месяц и его
   CPU-утилизацию; решите, есть ли там overprovisioning.

---

## Проверка модуля

```bash
bash verify/verify.sh
# [OK] HNC: иерархия работает, RBAC распространяется parent -> child
# [OK] vcluster: API доступен
# [OK] vcluster: под из виртуального кластера реально работает в host (syncer)
# [OK] module 28 verified
```

Уборка:

```bash
bash verify/cleanup.sh
```

---

## Шпаргалка

```bash
# --- HNC ---
kubectl apply -f - <<'Y'                       # вложить существующий ns
apiVersion: hnc.x-k8s.io/v1alpha2
kind: HierarchyConfiguration
metadata: {name: hierarchy, namespace: CHILD}
spec: {parent: PARENT}
Y
kubectl get subns -n PARENT                    # якоря (субнеймспейсы)
kubectl get ns CHILD --show-labels             # дерево: *.tree.hnc.x-k8s.io/depth
kubectl delete subns NAME -n PARENT            # удалить субнеймспейс

# --- vcluster ---
kubectl get secret vc-my-vcluster -n lab -o jsonpath='{.data.config}' | base64 -d > vc.yaml
kubectl -n lab port-forward svc/my-vcluster 18443:443 &
kubectl --kubeconfig vc.yaml get ns            # мир тенанта
kubectl -n lab get pods                        # тени: <pod>-x-<ns>-x-<vcluster>

# --- FinOps ---
# стоимость ns, $/час (1 vCPU·ч=$0.0112, 1 GiB·ч=$0.0028 — прайс стенда)
sum by (namespace) (kube_pod_container_resource_requests{resource="cpu",unit="core"}) * 0.0112
  + sum by (namespace) (kube_pod_container_resource_requests{resource="memory",unit="byte"}) / 2^30 * 0.0028
# фактическое потребление CPU
sum by (namespace) (rate(container_cpu_usage_seconds_total{container!=""}[10m]))
```

---

## Финальная карта ресурсов модуля

| Ресурс | Где | Назначение |
|--------|-----|------------|
| `manifests/01-vcluster.yaml` | ns `lab` | vcluster 0.34.2 (vendored helm-рендер, см. шапку) |
| `helm-values.yaml` | репо | values для перегенерации рендера |
| `manifests/02-hnc.yaml` | ns `hnc-system` | HNC v1.1.0 (vendored) |
| `broken/scenario-01/` + `solutions/01-host-quota/` | vcluster | инцидент: host-квота против тенанта |
| `tasks/01..03` | — | HNC, vcluster, FinOps-PromQL |
| `verify/{prepare,verify,cleanup}.sh` | — | QA-контракт модуля |
