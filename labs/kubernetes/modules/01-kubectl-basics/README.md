# Лабораторная работа 01: Основы kubectl и навигация по кластеру

## Оглавление
<!-- TOC -->
- [Предварительные требования](#-)
- [Стартовая проверка](#-)
- [Часть 1: API-центричная модель и устройство кластера](#-1-api-----)
  - [Теория для изучения перед частью](#----)
  - [1.1 kubeconfig и контексты](#11-kubeconfig--)
  - [1.2 Доказательство, что kubectl — это REST-клиент](#12---kubectl---rest-)
  - [1.3 Карта API: ресурсы, версии, схема](#13--api---)
- [Часть 2: Namespaces и организация ресурсов](#-2-namespaces---)
  - [Теория для изучения перед частью](#----)
  - [2.1 Просмотр и создание namespace](#21----namespace)
  - [2.2 Namespaced или нет](#22-namespaced--)
  - [2.3 Namespace по умолчанию в контексте](#23-namespace----)
- [Часть 3: Декларативное развёртывание приложения](#-3---)
  - [Теория для изучения перед частью](#----)
  - [3.1 Применение манифестов](#31--)
  - [3.2 Иерархия владения Deployment → ReplicaSet → Pod](#32---deployment--replicaset--pod)
  - [3.3 Как Service находит поды: selector → Endpoints](#33--service---selector--endpoints)
  - [3.4 Проверка DNS-резолва сервиса](#34--dns--)
  - [3.5 Императивно vs декларативно](#35--vs-)
- [Часть 4: Цикл диагностики — get → describe → logs → exec](#-4----get--describe--logs--exec)
  - [Теория для изучения перед частью](#----)
  - [4.1 get — широкий обзор состояния](#41-get----)
  - [4.2 describe — почему состояние именно такое](#42-describe-----)
  - [4.3 logs — что говорит приложение](#43-logs----)
  - [4.4 exec — внутрь контейнера](#44-exec---)
  - [4.5 port-forward — проверить приложение без Service](#45-port-forward-----service)
- [Часть 5: Troubleshooting — боевые инциденты](#-5-troubleshooting---)
  - [Теория для изучения перед частью](#----)
  - [Инцидент 1: под `Running`, но Service не отдаёт трафик](#-1--running--service---)
  - [Инцидент 2: `ImagePullBackOff` — образ не тянется](#-2-imagepullbackoff----)
  - [Инцидент 3: `CrashLoopBackOff` — контейнер падает в цикле](#-3-crashloopbackoff-----)
  - [Бонус: быстрая общая диагностика](#---)
- [Проверка модуля](#-)
- [Финальная карта ресурсов модуля](#---)
- [Теоретические вопросы (итоговые)](#--)
  - [Блок 1: API-модель и архитектура](#-1-api---)
  - [Блок 2: Контексты и namespace](#-2---namespace)
  - [Блок 3: Deployment, Service, связность](#-3-deployment-service-)
  - [Блок 4: Диагностика](#-4-)
- [Практические задания (отработка)](#--)
- [Шпаргалка](#)
- [Чему вы научились](#--)
<!-- /TOC -->


> ⏱ время ~15 мин · сложность 1/5 · пререквизиты: базовое знание Linux и Docker

Цель: научиться уверенно ориентироваться в кластере, понимать API-центричную
модель Kubernetes и владеть базовым циклом диагностики `get → describe → logs → exec`.
К концу модуля вы за несколько минут поднимаете приложение
(`Deployment + Service`) и самостоятельно локализуете причину, по которой
`Running`-под не обслуживает трафик.

---

## Предварительные требования

```bash
# kubeconfig нашего кластера (Kubespray); на другом стенде — свой путь/контекст
export KUBECONFIG=/root/.kube/kubespray.conf
# 1) Рабочий кластер и kubectl, который в него смотрит.
#    Подойдёт любой кластер, который РЕАЛЬНО запускает контейнеры:
#    kind, minikube, k3s/k3d, Docker Desktop или облачный (GKE/EKS/AKS).
kubectl version --output=yaml | head -20

# 2) Должен быть ровно один текущий контекст. Если контекстов несколько —
#    убедитесь, что активен учебный, а не production.
kubectl config current-context

# 3) Утилиты для удобства (не обязательны, но дальше используются):
#    - jq для разбора JSON-вывода;
#    - watch для слежения за состоянием в реальном времени.
which jq watch || echo "jq/watch желательны, но не критичны"
```

> **Что за «дистрибутивы» k8s** (встретятся по всему курсу): **kind/minikube/k3s** —
> локальные песочницы на одной машине (быстро поднять/снести); **GKE/EKS/AKS** —
> управляемые кластеры в облаке (Google/Amazon/Azure); **Kubespray** — разворачивает
> полноразмерный production-like кластер на ваших VM (наш учебный стенд). Сам
> Kubernetes и команды `kubectl` везде одинаковы — отличается только КАК поднят кластер.
>
> **Про учебный стенд.** Этот модуль рассчитан на кластер, где поды
> по-настоящему запускаются (kind/minikube/k3s/GKE). На «ненастоящих» стендах,
> которые лишь показывают объекты в API, но не выполняют контейнеры,
> `readinessProbe`, `logs` и `exec` не отработают. Все «ожидаемые выводы»
> ниже приведены для типового кластера (kube-dns на `10.96.0.10`,
> CNI выдаёт Pod IP из `10.20.0.0/16` либо `10.244.0.0/16`).

---

## Стартовая проверка

```bash
# Базовая связность с control-plane: где apiserver и сервисы кластера
kubectl cluster-info
# Kubernetes control plane is running at https://127.0.0.1:6443
# CoreDNS is running at https://127.0.0.1:6443/api/v1/.../kube-dns:dns/proxy

# Сколько нод и какие они
kubectl get nodes -o wide
# NAME                STATUS   ROLES           AGE   VERSION   INTERNAL-IP   OS-IMAGE             CONTAINER-RUNTIME
# kind-control-plane  Ready    control-plane   5d    v1.29.2   172.18.0.2    Debian GNU/Linux 12  containerd://1.7.x

# Все «системные» поды кластера — это и есть control-plane + сетевой слой
kubectl -n kube-system get pods
# coredns-..., etcd-..., kube-apiserver-..., kube-controller-manager-...,
# kube-proxy-..., kube-scheduler-...  — все в Running
```

> Если `kubectl get nodes` показывает `NotReady` — кластер не готов (чаще всего
> ещё не поднялся CNI). Дождитесь `Ready` прежде чем продолжать: на `NotReady`
> ноду scheduler не поставит ваши поды.

---

## Часть 1: API-центричная модель и устройство кластера

### Теория для изучения перед частью

- **Всё через API.** `kubectl` — это HTTP-клиент к `kube-apiserver`. Любая
  команда превращается в REST-запрос (`GET/POST/PATCH/DELETE`) к ресурсу API.
  Прямого «управления нодами» у `kubectl` нет — он только меняет объекты в API.
- **Control-plane:** `kube-apiserver` (единая точка входа, валидация, запись),
  `etcd` (хранит ВСЁ состояние кластера), `kube-scheduler` (выбирает ноду для
  Pod), `kube-controller-manager` (контроллеры, приводящие фактическое
  состояние к желаемому).
- **Узловой слой (на каждой ноде):** `kubelet` (запускает контейнеры через
  container runtime, следит за здоровьем), `kube-proxy` (реализует Service на
  уровне сети ноды), CNI-плагин (выдаёт Pod IP и связывает поды между нодами).
- **Desired state / reconciliation.** Вы декларируете «хочу N реплик», запись
  ложится в `etcd`, контроллеры непрерывно сравнивают желаемое с фактическим и
  устраняют разницу. Это фундамент всей модели.
- **kubeconfig:** файл (`~/.kube/config`), описывающий тройки
  *cluster + user + namespace = context*. Активный контекст определяет, КУДА и
  ОТ КОГО летят запросы.

**Архитектура кластера (кто где):**

```
          ┌──────────────── CONTROL-PLANE (k8s-cp-1) ───────────────┐
 kubectl  │  kube-apiserver ──────────────> etcd (ИСТОЧНИК ИСТИНЫ)  │
 ──REST──>┤        ▲     ▲                                          │
          │        │     └─ kube-scheduler (выбирает ноду для Pod)  │
          │        └──────── controller-manager (reconcile-петли)   │
          └──────────┬───────────────────────────────────────────────┘
                     │ apiserver — единственный, кто пишет в etcd; ноды «тянут» задания
          ┌──────────▼ WORKER-НОДЫ (k8s-w-1 / k8s-w-2) ──────────────┐
          │  kubelet (запускает контейнеры через containerd)         │
          │  kube-proxy (правила Service на ноде)   CNI (Pod IP)     │
          └──────────────────────────────────────────────────────────┘
```

**Путь запроса внутри apiserver** (где «рождаются» ошибки доступа):

```
kubectl apply ──HTTP──> kube-apiserver:
   1. Authentication — КТО ты   (cert / token / OIDC)        -> 401 если не опознан
   2. Authorization  — МОЖНО ли (RBAC: verb × resource)      -> 403 Forbidden (модуль 07)
   3. Admission      — мутация + валидация (PSA, VAP, webhook -> модуль 14)
   4. Validation + persist — записать объект в etcd
   <- ответ. Дальше scheduler/контроллеры РЕАГИРУЮТ на изменение (reconcile).
```

**Каталог ошибок по этапу — текст ошибки сразу говорит, ГДЕ чинить:**

| Симптом / текст | Этап | Причина | Что делать |
|---|---|---|---|
| `Unauthorized` (**401**) | AuthN | сертификат/токен невалиден, протух, не тот кластер | проверить kubeconfig (`kubectl config view`), срок cert |
| `error: You must be logged in` | AuthN | нет/битые credentials | перевыпустить kubeconfig |
| `Forbidden` (**403**) `User "X" cannot get resource "pods"` | AuthZ | RBAC не даёт verb на resource | `kubectl auth can-i <verb> <res>`; добавить Role/Binding (м07) |
| `forbidden: violates PodSecurity "restricted"` | Admission | PSA-профиль namespace | привести securityContext (м14) |
| `admission webhook "X" denied the request` | Admission | внешний webhook (Kyverno/Gatekeeper) | смотреть политику движка (м14) |
| `Invalid value` / `Required value` | Validation | объект не проходит схему (типы, required, CEL) | исправить манифест/CR (м19) |
| `AlreadyExists` (409) | persist | объект с таким именем есть | `apply` вместо `create` / другое имя |

> Главный инструмент для AuthZ-этапа — **`kubectl auth can-i`**: проверяет право
> БЕЗ выполнения действия (`kubectl auth can-i delete pods -n lab`;
> `--as=system:serviceaccount:lab:pod-reader` — от имени SA). 401 ≠ 403:
> **401** = «не понял, кто ты» (AuthN), **403** = «понял, но нельзя» (AuthZ).

**API group/version.** Каждый ресурс адресуется как `group/version` + `Kind`:
core-группа (пустая) — `Pod`/`Service` (`apiVersion: v1`); именованные группы —
`Deployment` (`apps/v1`), `Job` (`batch/v1`), `Ingress` (`networking.k8s.io/v1`).
`kubectl api-versions` — список включённых group/version; `kubectl api-resources`
показывает, какой ресурс в какой группе и его `apiVersion` для манифеста.

#### Reconciliation loop — как именно «факт догоняет желаемое»

Reconcile — не разовое действие на ваш `apply`, а **бесконечный цикл**, который
каждый контроллер крутит для своих объектов:

```
        ┌──────────────────────────────────────────────┐
        │                                              │
        ▼                                              │
   1. OBSERVE   читает желаемое (spec) и фактическое   │
      (watch)   (status) состояние из apiserver        │
        │                                              │
        ▼                                              │
   2. DIFF      сравнивает: spec.replicas=3, а Pod-ов 2 │
        │                                              │
        ▼                                              │
   3. ACT       создаёт/удаляет ресурсы, чтобы устранить│
                разницу (создать 1 Pod)                 │
        │                                              │
        └──────────► пишет status обратно в apiserver ─┘
                     и цикл повторяется снова и снова
```

- **Level-triggered, не edge-triggered.** Контроллер реагирует на *текущее
  состояние* («сейчас 2 пода, а надо 3»), а не на *событие* («кто-то удалил под»).
  Поэтому пропущенное событие не ломает систему: следующий проход цикла всё равно
  увидит расхождение и починит. Отсюда же **идемпотентность** — повторный
  reconcile при уже верном состоянии не делает ничего.
- **Watch/informer.** Чтобы не опрашивать apiserver в лоб (`list` в цикле),
  контроллеры держат **watch**-подписку и локальный кэш (informer). apiserver
  присылает дельты, кэш обновляется, объект кладётся в очередь на reconcile.
- **Каскад контроллеров.** Один `apply` запускает цепочку реконсайлов разных
  контроллеров, каждый отвечает за свой слой:

  | Объект | Контроллер | Что приводит к желаемому |
  |---|---|---|
  | Deployment | deployment-controller | создаёт/обновляет ReplicaSet под нужную ревизию |
  | ReplicaSet | replicaset-controller | держит N Pod-ов (создаёт/удаляет) |
  | Pod | scheduler + kubelet | scheduler выбирает ноду, kubelet запускает контейнеры |
  | Job/StatefulSet/DaemonSet | свои контроллеры | та же петля для своей семантики |
  | CRD (WebApp и т.п.) | ваш оператор | reconcile кастомного ресурса (модуль 19) |
  | Argo CD Application | argocd app-controller | git = желаемое, кластер = факт (модуль 09) |

> Reality: удалите под из Deployment — replicaset-controller на следующем проходе
> увидит «реплик меньше, чем в spec» и создаст новый (отработка в модуле 03).
> Argo CD selfHeal — тот же принцип, только «желаемое» лежит в git (модуль 09).

---

**Цель:** увидеть, что `kubectl` — это API-клиент, и научиться читать, в какой
кластер и под каким пользователем вы работаете.

---

### 1.1 kubeconfig и контексты

```bash
# Список контекстов (звёздочка = текущий)
kubectl config get-contexts
# CURRENT   NAME        CLUSTER     AUTHINFO    NAMESPACE
# *         kind-lab    kind-lab    kind-lab

# Только имя текущего контекста (удобно в скриптах/приглашении PS1)
kubectl config current-context

# Из чего состоит текущий контекст: кластер (адрес apiserver) и пользователь
kubectl config view --minify
# clusters: server: https://127.0.0.1:6443
# contexts: cluster/user/namespace
# users:    client-certificate-data / token

# Переключение контекста (если их несколько)
# kubectl config use-context <name>
```

> kubeconfig собирается из переменной `$KUBECONFIG` (может перечислять несколько
> файлов через `:`) или из `~/.kube/config` по умолчанию. `--minify` оставляет
> только активный контекст — это первое, что стоит показать, когда «команда
> выполняется не в том кластере».

### 1.2 Доказательство, что kubectl — это REST-клиент

```bash
# Поднять уровень логирования: -v=6 печатает каждый HTTP-вызов к apiserver
kubectl get nodes -v=6 2>&1 | grep -E "GET|round_trippers"
# GET https://127.0.0.1:6443/api/v1/nodes?limit=500 200 OK in 12 ms
#     ^ обычный REST-запрос; ответ — JSON, kubectl лишь форматирует его в таблицу

# -v=8 покажет тело запроса/ответа целиком (полезно при отладке RBAC/webhook'ов)
# kubectl get nodes -v=8
```

### 1.3 Карта API: ресурсы, версии, схема

```bash
# Все типы ресурсов кластера: короткое имя, apiVersion, namespaced (да/нет), Kind
kubectl api-resources | head -20
# NAME         SHORTNAMES   APIVERSION   NAMESPACED   KIND
# pods         po           v1           true         Pod
# services     svc          v1           true         Service
# deployments  deploy       apps/v1      true         Deployment
# nodes        no           v1           false        Node      <- кластерный, без namespace

# Какие группы/версии API включены на этом кластере
kubectl api-versions | sort | head -20

# Документация по полям прямо из apiserver (схема OpenAPI), без интернета
kubectl explain deployment.spec.replicas
# FIELD: replicas <integer>
# DESC:  Number of desired pods...

# Сначала — описание самого поля и его прямых под-полей (читабельно):
kubectl explain pod.spec.containers
# KIND: Pod ... FIELDS: name <string>, image <string>, ports <[]Object>, ...

# Затем, при необходимости, развернуть ВСЮ вложенную схему (флаг --recursive даёт
# большую «простыню» — её обычно смотрят точечно через | grep <поле>):
kubectl explain pod.spec.containers --recursive | head -30
```

> `kubectl explain` берёт схему из самого кластера, поэтому она ВСЕГДА
> соответствует версии вашего apiserver. Это надёжнее, чем гуглить поля: на
> разных версиях набор полей отличается.

**Контрольные вопросы:**
1. Почему `kubectl` называют API-клиентом, а не инструментом управления нодами?
2. Что произойдёт со всем состоянием кластера, если потерять данные `etcd`?
3. Что именно меняет активный контекст в kubeconfig и почему это первое, что
   нужно проверять при «странном» поведении команд?
4. Чем `kubectl api-resources` принципиально полезнее, чем заученный список
   ресурсов? Как по нему понять, namespaced ресурс или нет?
5. Какую информацию покажет `kubectl get pods -v=8`, чего не видно при `-v=0`?

---

## Часть 2: Namespaces и организация ресурсов

### Теория для изучения перед частью

- **Namespace** — логическая граница внутри одного кластера: имена ресурсов
  уникальны в пределах namespace, а не всего кластера. Служит для изоляции
  команд/окружений и для квот/RBAC.
- **Стартовые namespace:** `default` (по умолчанию), `kube-system`
  (control-plane и аддоны), `kube-public` (публично читаемые данные),
  `kube-node-lease` (heartbeat'ы нод).
- **Namespaced vs cluster-scoped.** Pod, Service, Deployment живут в namespace.
  Node, PersistentVolume, StorageClass, Namespace — кластерные, namespace у них
  нет.
- **Контекст несёт namespace по умолчанию.** Можно «прибить» рабочий namespace к
  контексту, чтобы не писать `-n` в каждой команде.
- **Навигация по namespace:** `-n <ns>` — конкретный; `-A`/`--all-namespaces` —
  ПО ВСЕМ сразу (добавляет колонку NAMESPACE) — незаменимо для «где вообще этот под
  по всему кластеру»: `kubectl get pods -A`, `kubectl get pods -A | grep -v Running`.

---

**Цель:** научиться видеть и создавать namespace и понимать, какие ресурсы ему
подчиняются, а какие — нет.

**Namespace лабы:** `lab`

---

### 2.1 Просмотр и создание namespace

```bash
# Какие namespace уже есть
kubectl get ns
# NAME              STATUS   AGE
# default           Active   5d
# kube-node-lease   Active   5d
# kube-public       Active   5d
# kube-system       Active   5d

# Идемпотентно создать namespace lab:
# create ns ... --dry-run=client -o yaml  -> генерирует манифест, НЕ трогая кластер
# apply -f -                              -> применяет; повторный запуск не упадёт
kubectl create ns lab --dry-run=client -o yaml | kubectl apply -f -
# namespace/lab created   (на повторе: namespace/lab unchanged)

# Навесить label — пригодится для отбора и политик
kubectl label ns lab owner=student --overwrite

kubectl get ns lab --show-labels
# NAME   STATUS   AGE   LABELS
# lab    Active   8s    kubernetes.io/metadata.name=lab,owner=student
```

> Связка `--dry-run=client -o yaml | kubectl apply -f -` — идиома
> идемпотентного создания: в отличие от голого `kubectl create ns lab` (упадёт с
> `AlreadyExists` на повторе), `apply` повторно проходит без ошибки. Это важно
> для скриптов и verify.

### 2.2 Namespaced или нет

```bash
# Ресурсы, ПРИВЯЗАННЫЕ к namespace
kubectl api-resources --namespaced=true | head -10
# pods, services, deployments, configmaps, secrets, ...

# Ресурсы КЛАСТЕРНОГО уровня (namespace к ним неприменим)
kubectl api-resources --namespaced=false | head -10
# namespaces, nodes, persistentvolumes, storageclasses, clusterroles, ...

# Поэтому это вернёт ошибку — у Node нет namespace:
kubectl -n lab get node    # -n игнорируется для кластерных ресурсов
```

### 2.3 Namespace по умолчанию в контексте

```bash
# Прибить namespace lab к текущему контексту, чтобы не писать -n каждый раз
kubectl config set-context --current --namespace=lab
# Context "kind-lab" modified.

# Теперь без -n команды идут в lab
kubectl get pods            # эквивалент kubectl -n lab get pods

# Вернуть default, когда закончите модуль:
# kubectl config set-context --current --namespace=default
```

> Удобный временный приём вместо изменения контекста — алиас:
> `alias kl='kubectl -n lab'`. В примерах ниже namespace указан явно через `-n lab`,
> чтобы команды были самодостаточны и копировались в любой контекст.

**Контрольные вопросы:**
1. Почему имена подов могут совпадать в разных namespace, но не внутри одного?
2. Какие из ресурсов кластерные, а не namespaced: Pod, Node, Service,
   StorageClass, Deployment, PersistentVolume?
3. Чем `kubectl create ns lab` отличается от связки
   `--dry-run=client -o yaml | kubectl apply -f -` при повторном запуске?
4. Что делает `kubectl config set-context --current --namespace=lab` и почему
   это безопаснее, чем «забыть» про `-n`?

---

## Часть 3: Декларативное развёртывание приложения

### Теория для изучения перед частью

- **Deployment → ReplicaSet → Pod.** Вы описываете `Deployment`, он создаёт
  `ReplicaSet`, тот поддерживает заданное число `Pod`. Связь — через
  `ownerReferences` (видно в `metadata`).
- **Labels и selectors.** `Deployment.spec.selector` и `Service.spec.selector`
  отбирают поды по labels. Это «клей» всей системы: ничего не привязывается по
  именам — только по labels.
- **Service и Endpoints.** `Service` даёт стабильный виртуальный IP (ClusterIP).
  Контроллер endpoints наполняет объект `Endpoints` адресами подов, которые
  (а) подходят под selector и (б) прошли `readinessProbe`. Нет готовых подов —
  нет backend'ов.
- **Императивно vs декларативно.** `kubectl create/run` — императивно (разово
  «сделай»). `kubectl apply -f` — декларативно (привести к описанному в файле);
  именно так работают в GitOps и проде.

| | Императивно (`create`/`run`/`edit`/`scale`) | Декларативно (`apply -f`) |
|---|---|---|
| Что говоришь | «сделай действие» | «приведи к ЭТОМУ состоянию» |
| Повторный запуск | падает (`AlreadyExists`) | идемпотентно (`unchanged`) |
| Источник истины | твоя память/история команд | файл (можно в git) |
| Слияние правок | перезатирает | 3-way merge (бережёт чужие поля) |
| Когда | быстрый эксперимент, генерация YAML (`--dry-run=client -o yaml`) | прод, GitOps, CI |

> Хорошая практика: императивом ГЕНЕРИРУЮТ стартовый YAML
> (`kubectl create deploy x --image=… --dry-run=client -o yaml > deploy.yaml`),
> а живут уже на `apply -f`.

---

**Цель:** развернуть `Deployment + Service` в namespace `lab` и понять, как
labels связывают Service с подами.

**Ресурсы:** `Deployment/kb-web` (nginx, 1 реплика), `Service/kb-web` (ClusterIP).

---

### 3.1 Применение манифестов

Манифесты модуля (`manifests/app/`): `Deployment` из одного пода `nginx:1.27-alpine`
с `readinessProbe` на порт `80` и `Service` типа ClusterIP, пробрасывающий
`80 → 80`. Запускайте команды из каталога модуля.

```bash
# Применить Deployment и Service декларативно
kubectl -n lab apply -f manifests/app/deploy.yaml
kubectl -n lab apply -f manifests/app/svc.yaml
# deployment.apps/kb-web created
# service/kb-web created

# Дождаться, пока Deployment раскатится (все реплики Ready)
kubectl -n lab rollout status deploy/kb-web --timeout=120s
# deployment "kb-web" successfully rolled out

# Общий обзор созданного
kubectl -n lab get deploy,rs,po,svc -o wide
# NAME                     READY   UP-TO-DATE   AVAILABLE
# deployment.apps/kb-web   1/1     1            1
# NAME                                DESIRED   CURRENT   READY
# replicaset.apps/kb-web-7d9c...      1         1         1
# NAME                          READY   STATUS    RESTARTS   IP           NODE
# pod/kb-web-7d9c...-x2k4p      1/1     Running   0          10.244.0.7   kind-...
# NAME             TYPE        CLUSTER-IP      PORT(S)   SELECTOR
# service/kb-web   ClusterIP   10.96.123.45    80/TCP    app=kb-web
```

> Альтернатива «всё разом» — kustomize: `kubectl -n lab apply -k manifests/`
> (файл `manifests/kustomization.yaml` перечисляет оба ресурса). Результат тот же.

### 3.2 Иерархия владения Deployment → ReplicaSet → Pod

```bash
# Кто «родитель» у ReplicaSet — увидим ownerReference на Deployment
kubectl -n lab get rs -o jsonpath='{.items[0].metadata.ownerReferences[0].kind}{"\n"}'
# Deployment

# Кто «родитель» у Pod — ReplicaSet
kubectl -n lab get pod -l app=kb-web \
  -o jsonpath='{.items[0].metadata.ownerReferences[0].kind}{"\n"}'
# ReplicaSet

# Labels подов — то, по чему их отберёт Service
kubectl -n lab get pods --show-labels
# kb-web-...   1/1   Running   app=kb-web,pod-template-hash=7d9c...
```

> Поэтому удаление пода не «убивает» приложение: ReplicaSet увидит расхождение с
> desired state и создаст замену. Управлять надо Deployment'ом, а не подами.

### 3.3 Как Service находит поды: selector → Endpoints

```bash
# У Service есть ClusterIP, но сам по себе он лишь правило. Реальные адреса —
# в объекте Endpoints, который наполняется ГОТОВЫМИ подами под selector.
kubectl -n lab get endpoints kb-web -o wide
# NAME     ENDPOINTS         AGE
# kb-web   10.244.0.7:80     30s    <- IP пода : порт; есть адрес => трафик пойдёт

# describe сводит вместе selector, порты и список endpoints
kubectl -n lab describe svc kb-web
# Selector:    app=kb-web
# Endpoints:   10.244.0.7:80
```

> Запомните цепочку: **labels пода ⊃ selector сервиса** + под **Ready** ⇒ его IP
> попадает в `Endpoints` ⇒ Service маршрутизирует на него. Сломайте любое звено —
> и `Endpoints` опустеет (ровно это разбираем в Части 5).

### 3.4 Проверка DNS-резолва сервиса

```bash
# Внутрикластерный DNS даёт сервису имя <svc>.<ns>.svc.cluster.local.
# Поднимем одноразовый debug-под и резолвим имя оттуда:
kubectl -n lab run dnscheck --image=busybox:1.36 --restart=Never -i --rm -- \
  nslookup kb-web.lab.svc.cluster.local
# Server:    10.96.0.10        <- ClusterIP kube-dns/CoreDNS
# Name:      kb-web.lab.svc.cluster.local
# Address:   10.96.123.45      <- ClusterIP сервиса kb-web
```

> `-i --rm` подключает stdin и удаляет под после выхода — чистый способ
> разово что-то проверить «изнутри» сети кластера. Если резолв не идёт —
> проблема в CoreDNS (`kubectl -n kube-system logs deploy/coredns`), а не в вашем сервисе.

### 3.5 Императивно vs декларативно

```bash
# Сгенерировать манифест Deployment, НЕ создавая его (--dry-run=client):
kubectl create deployment tmp --image=nginx:1.27-alpine \
  --dry-run=client -o yaml | head -15
# Удобно как стартовый шаблон вместо написания YAML с нуля.

# apply можно прогонять многократно — это декларативно: приводит кластер к файлу.
kubectl -n lab apply -f manifests/app/deploy.yaml
# deployment.apps/kb-web unchanged   <- идемпотентно, второй apply ничего не ломает
```

**Контрольные вопросы:**
1. Опишите цепочку Deployment → ReplicaSet → Pod. Что произойдёт, если удалить
   один Pod руками?
2. По какому признаку `Service` отбирает поды? Почему привязка идёт по labels, а
   не по именам подов?
3. Что хранится в объекте `Endpoints` и при каком условии IP пода туда попадает?
4. Чем `kubectl apply -f` отличается от `kubectl create -f` при повторном
   применении того же файла?
5. Что вернёт полное DNS-имя `kb-web.lab.svc.cluster.local` и какой компонент
   кластера за это отвечает?

---

## Часть 4: Цикл диагностики — get → describe → logs → exec

### Теория для изучения перед частью

- **Четыре глагола, четыре вопроса.** `get` — «что есть?», `describe` —
  «почему так?» (включая events), `logs` — «что говорит приложение?», `exec` —
  «что внутри контейнера прямо сейчас?».
- **Events живут 1 час.** В хвосте `describe` и в `kubectl get events` — самая
  ценная диагностика (расписание, pull образа, проба, OOM). По умолчанию
  хранятся ~60 минут, потом исчезают.
- **Форматы вывода.** `-o wide` (доп. колонки), `-o yaml` (полный объект как в
  etcd), `-o jsonpath`/`-o custom-columns` (точечно вытащить поле),
  `--show-labels`, `-w` (следить в реальном времени).

| Формат | Что даёт | Когда |
|--------|----------|-------|
| (по умолчанию) | таблица | беглый обзор |
| `-o wide` | + IP, нода, образ | «где сидит / какой образ» |
| `-o yaml` | ВЕСЬ объект (spec+status+managedFields) | разбор/копирование манифеста |
| `-o jsonpath='{...}'` | одно поле/срез | скрипты (`{.status.podIP}`) |
| `-o custom-columns=…` | свои колонки | таблица под задачу |
| `--show-labels` / `-L key` | labels | отбор по меткам |
| `-w` | поток изменений | следить за раскаткой |

- **Доступ внутрь.** `exec` (выполнить в контейнере), `logs --previous`
  (логи прошлого, упавшего контейнера), `port-forward` (пробросить порт
  локально, не создавая Service).
- **`kubectl debug` (ephemeral containers, GA 1.25).** Когда в поде нет shell
  (distroless) или под крашится — `kubectl debug -it <pod> --image=busybox
  --target=<container>` подсаживает ВРЕМЕННЫЙ контейнер в тот же namespace пода
  (видит его процессы/сеть), не пересоздавая под. Для отладки ноды —
  `kubectl debug node/<node> -it --image=busybox`.

---

**Цель:** отработать базовый цикл диагностики на живом `kb-web`.

---

### 4.1 get — широкий обзор состояния

```bash
# Всё основное в namespace разом
kubectl -n lab get all
# pod/..., service/..., deployment.apps/..., replicaset.apps/...

# Расширенные колонки: IP, нода, образ
kubectl -n lab get pods -o wide

# Точечно вытащить поле через jsonpath (тут — образ контейнера)
kubectl -n lab get deploy kb-web \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
# nginx:1.27-alpine

# Полный объект, как он лежит в etcd (со status, managedFields и т.д.)
kubectl -n lab get pod -l app=kb-web -o yaml | head -40

# Следить за изменением статуса в реальном времени (Ctrl+C для выхода)
kubectl -n lab get pods -w
```

### 4.2 describe — почему состояние именно такое

```bash
# describe пода: образ, порты, probes, ресурсы и — в хвосте — Events
kubectl -n lab describe pod -l app=kb-web
# Containers: nginx: Image: nginx:1.27-alpine; Port: 80/TCP
#   Readiness: http-get http://:80/ delay=3s period=5s
#   Limits/Requests: cpu/memory
# Conditions: Ready True
# Events: Scheduled -> Pulled -> Created -> Started

# describe Deployment покажет стратегию обновления и связанный ReplicaSet
kubectl -n lab describe deploy kb-web | grep -A3 "StrategyType"
```

> В `describe` смотрите на блок **Events** в самом низу — 80% причин «почему под
> не поднялся» написаны именно там человеческим текстом.

### 4.3 logs — что говорит приложение

```bash
# Логи пода (nginx пишет access/error в stdout/stderr)
kubectl -n lab logs deploy/kb-web --tail=50
# обращение к / от readiness-пробы: "GET / HTTP/1.1" 200

# Следить за логами в реальном времени
kubectl -n lab logs -f deploy/kb-web

# Логи ПРЕДЫДУЩЕГО (упавшего) контейнера — ключ к разбору CrashLoopBackOff
# kubectl -n lab logs <pod> --previous
```

> `deploy/kb-web` в `logs` означает «возьми логи пода за этим Deployment».
> Для упавшего контейнера обычный `logs` покажет логи НОВОГО запуска — нужен
> `--previous`, чтобы увидеть, почему упал прошлый.

### 4.4 exec — внутрь контейнера

```bash
# Разовая команда внутри контейнера
kubectl -n lab exec deploy/kb-web -- nginx -v
# nginx version: nginx/1.27.x

# Посмотреть, на каком порту реально слушает процесс внутри пода
kubectl -n lab exec deploy/kb-web -- sh -c 'ls /etc/nginx/conf.d/ && cat /etc/nginx/conf.d/default.conf | grep listen'
# listen 80;     <- подтверждаем порт 80; пригодится в Части 5

# Интерактивная сессия (выход — exit)
kubectl -n lab exec -it deploy/kb-web -- sh
```

### 4.5 port-forward — проверить приложение без Service

```bash
# Пробросить локальный порт 8080 на порт 80 пода
kubectl -n lab port-forward deploy/kb-web 8080:80 &
sleep 2
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8080/
# 200
kill %1   # остановить проброс
```

**Контрольные вопросы:**
1. Сопоставьте глагол и вопрос: `get` / `describe` / `logs` / `exec` — что
   спрашиваете каждым?
2. Где в выводе `describe pod` искать причину, по которой под не запустился?
3. Зачем нужен `kubectl logs --previous` и когда обычный `logs` бесполезен?
4. Чем `port-forward` отличается от `Service` как способ достучаться до пода?
5. Как одной командой узнать образ контейнера, не открывая полный YAML?

---

## Часть 5: Troubleshooting — боевые инциденты

### Теория для изучения перед частью

- **readiness ≠ liveness.** `readinessProbe` решает, готов ли под ПРИНИМАТЬ
  трафик (управляет членством в `Endpoints`). `livenessProbe` решает, надо ли
  ПЕРЕЗАПУСТИТЬ контейнер. Провал readiness НЕ рестартует под — он просто
  выпадает из сервиса.
- **`Running` ≠ `Ready`.** Колонка `READY 0/1` при `STATUS Running` означает:
  процесс жив, но пробы не пройдены. Смотреть надо на `READY`, а не на `STATUS`.
- **Типовые статусы и где копать:** `Pending` (некуда/нечем расписать — events
  пода), `ImagePullBackOff`/`ErrImagePull` (не тянется образ — events),
  `CrashLoopBackOff` (контейнер падает в цикле — `logs --previous`),
  `0/1 Running` (пробы не прошли — `describe`, блок Readiness/Events).

---

**Цель:** отработать локализацию причины на трёх классических отказах.

---

### Инцидент 1: под `Running`, но Service не отдаёт трафик

Это разобрано как отдельный сценарий в `broken/scenario-01/` (там же подсказки и
решение). Здесь — полный цикл диагностики.

**Воспроизведение:**

```bash
# Применяем заведомо сломанный вариант: readinessProbe смотрит на порт 8080,
# а nginx слушает 80.
kubectl -n lab apply -f broken/scenario-01/deploy.yaml
sleep 12
```

**Диагностика:**

```bash
# 1) Под Running, но НЕ Ready — ключевой признак
kubectl -n lab get pods -l app=kb-web
# NAME           READY   STATUS    RESTARTS   AGE
# kb-web-...     0/1     Running    0          15s   <- 0/1: смотрим на READY, не на STATUS!

# 2) Endpoints сервиса ПУСТ — значит, Service не на кого маршрутизировать
kubectl -n lab get endpoints kb-web
# NAME     ENDPOINTS   AGE
# kb-web   <none>      ...        <- ни одного backend-адреса

# 3) Почему под не Ready — events и условие пробы
kubectl -n lab describe pod -l app=kb-web | grep -A4 -E "Readiness|Warning"
# Readiness probe failed: Get "http://10.244.0.9:8080/": connect: connection refused
#   ^ проба стучится на 8080, там никто не слушает -> под NotReady -> вне Endpoints
```

**Решение:**

```bash
# Чиним порт пробы 8080 -> 80 (готовый исправленный манифест)
kubectl -n lab apply -f solutions/01-wrong-port/deploy.yaml
kubectl -n lab rollout status deploy/kb-web --timeout=120s

# Endpoints наполнился — трафик пошёл
kubectl -n lab get endpoints kb-web -o wide
# kb-web   10.244.0.9:80   ...
```

**Профилактика:**

```bash
# Порт пробы ОБЯЗАН совпадать с containerPort, на котором реально слушает процесс.
# Проверять можно тем же exec (см. 4.4): cat default.conf | grep listen.
# Хорошая практика — именованный порт: ports.name: http + probe port: http,
# тогда число задаётся в одном месте.
```

### Инцидент 2: `ImagePullBackOff` — образ не тянется

**Воспроизведение:**

```bash
# Подменяем образ на несуществующий тег (типичная опечатка в CI/манифесте)
kubectl -n lab set image deploy/kb-web nginx=nginx:1.27-typo-not-exist
```

**Диагностика:**

```bash
kubectl -n lab get pods -l app=kb-web
# kb-web-<new>   0/1   ImagePullBackOff   0   20s

# Причина — в events пода
kubectl -n lab describe pod -l app=kb-web | grep -A2 -E "Failed|Back-off"
# Failed to pull image "nginx:1.27-typo-not-exist": ... not found
# Back-off pulling image "nginx:1.27-typo-not-exist"
```

**Решение и профилактика:**

```bash
# Вернуть рабочий образ (или откатить весь rollout)
kubectl -n lab set image deploy/kb-web nginx=nginx:1.27-alpine
kubectl -n lab rollout status deploy/kb-web --timeout=120s
# Профилактика: пинить точные теги/дайджесты, проверять доступность образа в CI,
# не использовать :latest (невоспроизводимо).
```

### Инцидент 3: `CrashLoopBackOff` — контейнер падает в цикле

**Воспроизведение:**

```bash
# Одноразовый под, чья команда сразу завершается с ошибкой
kubectl -n lab run crasher --image=busybox:1.36 --restart=Never -- \
  sh -c 'echo "boot..."; sleep 2; echo "fatal: config missing" >&2; exit 1'
sleep 15
```

**Диагностика:**

```bash
kubectl -n lab get pod crasher
# crasher   0/1   CrashLoopBackOff   2 (10s ago)   25s
#                  ^ kubelet ждёт всё дольше между рестартами (back-off)

# Логи ТЕКУЩего запуска могут быть пусты — нужен предыдущий, упавший:
kubectl -n lab logs crasher --previous
# boot...
# fatal: config missing      <- вот настоящая причина падения

# Подтверждение в describe: последний контейнер вышел с кодом 1
kubectl -n lab describe pod crasher | grep -A3 "Last State"
# Last State: Terminated  Reason: Error  Exit Code: 1
```

**Решение:**

```bash
# В реальной жизни — чинить причину из логов (конфиг/доступ/команду).
# Здесь просто убираем демонстрационный под:
kubectl -n lab delete pod crasher --ignore-not-found
```

### Бонус: быстрая общая диагностика

```bash
# Свежие события по namespace, по времени — общая «лента проблем»
kubectl -n lab get events --sort-by=.lastTimestamp | tail -15

# Все «нездоровые» поды по всему кластеру одной строкой
kubectl get pods -A --field-selector=status.phase!=Running | grep -v Completed

# Что вообще не Ready (по условию готовности)
kubectl get pods -A -o json | jq -r '
  .items[] | select(any(.status.conditions[]?; .type=="Ready" and .status!="True"))
  | "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null
```

**Контрольные вопросы:**
1. Под в статусе `Running`, но `READY 0/1`. Что это значит и куда смотреть
   первым делом?
2. Почему провал `readinessProbe` опустошает `Endpoints`, но не рестартует
   контейнер, а провал `livenessProbe` — рестартует?
3. При `CrashLoopBackOff` обычный `kubectl logs` часто бесполезен. Почему и чем
   его заменить?
4. Чем отличаются `ImagePullBackOff` и `ErrImagePull`? Где искать точную причину?
5. Что такое «back-off» в названии статусов и как он проявляется в колонке
   `RESTARTS`?

---

## Проверка модуля

Перед автопроверкой разверните рабочие (а не broken) манифесты и дождитесь
готовности:

```bash
# Рабочее приложение в namespace lab
kubectl -n lab apply -f manifests/app/deploy.yaml
kubectl -n lab apply -f manifests/app/svc.yaml
kubectl -n lab rollout status deploy/kb-web --timeout=120s

# Автопроверка модуля
bash verify/verify.sh
# [OK] module 01 verified
```

`verify/verify.sh` проверяет ровно цепочку из этого модуля: существует namespace
`lab` → `Deployment/kb-web` дошёл до Ready → есть `Service/kb-web` → у сервиса
непустые `Endpoints` (то есть под прошёл readiness и реально доступен).

Промежуточные проверки (`require_namespace`, `require_deployment_ready`,
`require_resource`, `require_service_endpoints`) при успехе **молчат** — печатается
только итоговая `[OK] module 01 verified`. При первом же провале скрипт (он под
`set -euo pipefail`) выведет `[FAIL] ...` с причиной и остановится. Например, если
оставить применённым broken-вариант из Части 5, проверка упадёт на
`[FAIL] service/kb-web has no ready endpoints in ns/lab` — пустой `Endpoints`
ловится ровно здесь.

---

## Финальная карта ресурсов модуля

| Ресурс | Тип | Namespace | Что демонстрирует |
|--------|-----|-----------|-------------------|
| `lab` | Namespace | — (кластерный) | Изоляция ресурсов, labels, namespace по умолчанию |
| `kb-web` | Deployment | `lab` | desired state, Deployment→RS→Pod, readinessProbe |
| `kb-web` | ReplicaSet (создаётся Deployment) | `lab` | ownerReferences, поддержание числа реплик |
| `kb-web` | Service (ClusterIP) | `lab` | selector→Endpoints, стабильный IP, DNS-имя |
| `dnscheck` | Pod (эфемерный, `--rm`) | `lab` | проверка внутрикластерного DNS |
| `crasher` | Pod (эфемерный) | `lab` | разбор `CrashLoopBackOff` (Инцидент 3) |

---

## Теоретические вопросы (итоговые)

### Блок 1: API-модель и архитектура

1. Объясните, почему любую операцию `kubectl` можно свести к REST-запросу к
   `kube-apiserver`. Что играет роль «источника истины» о состоянии кластера?
2. Распишите роли компонентов control-plane (`apiserver`, `etcd`, `scheduler`,
   `controller-manager`) и узлового слоя (`kubelet`, `kube-proxy`, CNI).
3. Что такое reconciliation loop (цикл согласования)? Приведите пример на
   Deployment: что произойдёт, если фактическое число подов меньше желаемого?

### Блок 2: Контексты и namespace

4. Из каких трёх сущностей состоит context в kubeconfig? Что изменится, если
   переключить контекст?
5. Чем namespaced-ресурс отличается от cluster-scoped? Приведите по три примера
   каждого.
6. Зачем «прибивать» namespace к контексту и какие риски у работы без явного
   `-n`?

### Блок 3: Deployment, Service, связность

7. Опишите цепочку Deployment → ReplicaSet → Pod и роль `ownerReferences`.
8. Как `Service` находит свои поды? Сформулируйте полное условие, при котором IP
   пода попадает в `Endpoints`.
9. Что вернёт `kubectl get endpoints <svc>`, если selector сервиса не совпадает
   ни с одним подом? А если поды есть, но не Ready?
10. Чем декларативный `apply` лучше императивного `create` для эксплуатации в
    проде/GitOps?

### Блок 4: Диагностика

11. Сопоставьте `get`/`describe`/`logs`/`exec` с типами вопросов, на которые они
    отвечают. Где в этой цепочке находятся events?
12. Под завис в `0/1 Running`. Опишите пошаговый план диагностики (какие команды
    и что в выводе искать).
13. Почему при `CrashLoopBackOff` нужен `logs --previous`, а не просто `logs`?
14. Как, не имея Service, проверить, что приложение в поде реально отвечает по
    HTTP?

---

## Практические задания (отработка)

> Делайте на живом кластере; проверяйте себя командами и `verify/verify.sh`.

1. Одной командой найдите ВСЕ поды по кластеру, что НЕ в `Running` (`get pods -A --field-selector` + grep).
2. Через `-o jsonpath` выведите образы всех контейнеров `deploy/kb-web` одной строкой.
3. Сломайте `readinessProbe` (неверный порт), затем по цепочке `get → describe → logs` локализуйте, почему `Endpoints` пуст.
4. Создайте namespace, «прибейте» его к контексту (`set-context --namespace`), поработайте без `-n`, верните `default`.
5. `kubectl explain pod.spec --recursive` — найдите 3 поля, которых не знали, и объясните назначение.

---

## Шпаргалка

```bash
# === Контекст и кластер ===
kubectl config get-contexts
kubectl config current-context
kubectl config view --minify
kubectl config set-context --current --namespace=lab
kubectl cluster-info
kubectl get nodes -o wide

# === Карта API ===
kubectl api-resources                 # все ресурсы: namespaced?, Kind, shortname
kubectl api-resources --namespaced=false   # только кластерные
kubectl explain <resource>.<field>    # схема полей из самого кластера

# === Namespace ===
kubectl get ns
kubectl create ns lab --dry-run=client -o yaml | kubectl apply -f -
kubectl label ns lab owner=student --overwrite

# === Развёртывание ===
kubectl -n lab apply -f manifests/app/deploy.yaml -f manifests/app/svc.yaml
kubectl -n lab apply -k manifests/          # то же через kustomize
kubectl -n lab rollout status deploy/kb-web --timeout=120s

# === get: обзор ===
kubectl -n lab get all
kubectl -n lab get pods -o wide --show-labels
kubectl -n lab get pod <p> -o jsonpath='{.spec.containers[0].image}'
kubectl -n lab get endpoints kb-web -o wide
kubectl -n lab get pods -w

# === describe / logs / exec / forward ===
kubectl -n lab describe pod -l app=kb-web        # причина — в блоке Events
kubectl -n lab logs deploy/kb-web --tail=100 -f
kubectl -n lab logs <pod> --previous             # логи упавшего контейнера
kubectl -n lab exec -it deploy/kb-web -- sh
kubectl -n lab port-forward deploy/kb-web 8080:80

# === Диагностика проблем ===
kubectl -n lab get events --sort-by=.lastTimestamp | tail -15
kubectl get pods -A --field-selector=status.phase!=Running
kubectl -n lab describe pod -l app=kb-web | grep -A4 -E "Readiness|Warning|Failed"

# === Уборка ===
kubectl -n lab delete -f manifests/app/svc.yaml -f manifests/app/deploy.yaml
kubectl config set-context --current --namespace=default
```

## Чему вы научились

В этом модуле вы научились:
- Базовым операциям с kubectl (get, describe, logs)
- Пониманию архитектуры API Kubernetes
- Императивному созданию ресурсов
