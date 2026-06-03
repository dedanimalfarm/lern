# Лабораторная работа 06: Планирование подов (nodeSelector, taints, affinity, quotas)

Цель: научиться управлять тем, на какую ноду попадёт Pod и сколько ресурсов он
сможет занять — через `nodeSelector`/labels, `taints`/`tolerations`,
`affinity`/`anti-affinity` и `ResourceQuota`/`LimitRange`. К концу модуля вы
читаете причину `Pending` в `FailedScheduling` и осознанно «приклеиваете» или
«отталкиваете» поды от нод.

---

## Предварительные требования

```bash
# kubeconfig нашего кластера (Kubespray); на другом стенде — свой путь/контекст
export KUBECONFIG=/root/.kube/kubespray.conf
# Чистый namespace lab (убрать ресурсы прошлых модулей)
kubectl -n lab delete deploy,sts,ds,job,cronjob,svc,pvc,pod,ingress,netpol,resourcequota,limitrange --all --ignore-not-found
kubectl create ns lab --dry-run=client -o yaml | kubectl apply -f -
```

### Подготовка нод (обязательно для verify!)

Часть манифестов требует РУЧНОЙ разметки нод — без неё поды не сядут и `verify`
упадёт. Выполните перед развёртыванием:

```bash
# Запомним имена двух WORKER-нод. ВАЖНО: исключаем control-plane — на ней по
# умолчанию стоит taint node-role.kubernetes.io/control-plane:NoSchedule, и под
# без toleration туда НЕ сядет. Без фильтра `items[0]` часто = control-plane
# (так на нашем Kubespray: items[0]=k8s-cp-1) -> select-by-label повис бы в Pending.
NODE_A=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}')
NODE_B=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[1].metadata.name}')
echo "NODE_A=$NODE_A  NODE_B=$NODE_B"   # обе должны быть worker-нодами (не *-cp-*)

# 1) label disktype=ssd — нужен для select-by-label (nodeSelector)
kubectl label node "$NODE_A" disktype=ssd --overwrite

# 2) taint dedicated=lab:NoSchedule — нужен для демо taints/tolerations
kubectl taint nodes "$NODE_B" dedicated=lab:NoSchedule --overwrite
```

> Это и есть суть модуля: размещение зависит от того, как размечены ноды.
> В конце (секция «Уборка») разметку обязательно снимаем, чтобы не влиять на
> другие модули.

---

## Стартовая проверка

```bash
# Ноды и их ключевые labels (на них опираются nodeSelector/affinity)
kubectl get nodes -L disktype,topology.kubernetes.io/zone
# NAME            STATUS   ROLES   ...   DISKTYPE   ZONE
# ...-b02f        Ready    <none>        ssd        us-central1-a
# ...-hj1s        Ready    <none>                   us-central1-a

# Taint'ы нод
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.taints}{"\n"}{end}'
# ...-hj1s   [{"effect":"NoSchedule","key":"dedicated","value":"lab"}]
```

---

## Часть 1: nodeSelector и labels нод

### Теория для изучения перед частью

- **Scheduler за два прохода:** сначала ФИЛЬТРУЕТ ноды по жёстким ограничениям
  (хватает ли ресурсов, проходит ли nodeSelector/affinity/taints), затем
  РАНЖИРУЕТ прошедших по «мягким» правилам и кладёт Pod на лучшую.
- **`nodeSelector`** — простейший жёсткий отбор: Pod сядет только на ноду, у
  которой есть ВСЕ указанные labels. Не нашлось — `Pending`.
- Labels на ноды вешают руками (`kubectl label node`) или их выставляет облако
  (например `topology.kubernetes.io/zone`, `node.kubernetes.io/instance-type`).

**Пайплайн планировщика (две фазы):**

```
Pod (Pending) ──> SCHEDULER
   │
   1. FILTER (предикаты): отсеять НЕподходящие ноды
   │     • хватает requests.cpu/memory?   • проходит nodeSelector/nodeAffinity?
   │     • taints толерируются?           • свободны hostPort?
   │     └─> «годные» ноды (feasible)
   2. SCORE (приоритеты): оценить годные 0..100
   │     • LeastAllocated (свободнее = выше)  • BalancedAllocation  • вес preferred-affinity
   3. BIND: лучшая нода -> pod.spec.nodeName -> kubelet запускает контейнеры
   │
   └─ если после FILTER годных НЕТ -> Pod остаётся Pending + событие FailedScheduling
```

```yaml
# nodeSelector в манифесте пода (это и есть фаза FILTER по label):
spec:
  nodeSelector:
    disktype: ssd        # сядет ТОЛЬКО на ноду с этим label; нет такой -> Pending
```

---

**Цель:** «приклеить» Pod к ноде по label.

**Ресурс:** `manifests/selectors/deploy.yaml` (`select-by-label`, nodeSelector
`disktype: ssd`).

---

### 1.1 Label ноды + nodeSelector

```bash
# (label disktype=ssd на NODE_A уже навешен в «Подготовке нод»)
kubectl -n lab apply -f manifests/selectors/deploy.yaml
kubectl -n lab rollout status deploy/select-by-label --timeout=120s

# Pod сел именно на ноду с disktype=ssd
kubectl -n lab get pod -l app=select-by-label -o wide
# NAME                 READY   STATUS    NODE
# select-by-label-...  1/1     Running   ...-b02f      <- это NODE_A с disktype=ssd
```

> Снимите label (`kubectl label node $NODE_A disktype-`) — и при пересоздании Pod
> уйдёт в `Pending`: подходящих нод не останется. Это ровно инцидент из Части 5.

**Контрольные вопросы:**
1. Опишите две фазы работы scheduler (фильтрация и ранжирование).
2. Что произойдёт с Pod, если ни одна нода не подходит под `nodeSelector`?
3. Чем `nodeSelector` отличается от `nodeName` (прямое указание ноды)?

---

## Часть 2: Taints и Tolerations

### Теория для изучения перед частью

- **taint** «отталкивает» поды от ноды. **toleration** на Pod — «разрешение» сесть
  на ноду с конкретным taint. Это НЕ принуждение (под не обязан садиться именно
  туда), а снятие запрета.
- Применение: выделенные ноды (GPU, dedicated), защита control-plane (там стоят
  системные taint'ы).

**Три эффекта taint:**

| Эффект | Новые поды БЕЗ toleration | Уже запущенные поды без toleration |
|--------|---------------------------|------------------------------------|
| `NoSchedule` | не сядут | остаются работать |
| `PreferNoSchedule` | избегаются (мягко, сядут если выбора нет) | остаются |
| `NoExecute` | не сядут | **ВЫСЕЛЯЮТСЯ** (с `tolerationSeconds` — через паузу) |

```yaml
# toleration на поде — снимает запрет конкретного taint (dedicated=lab:NoSchedule):
spec:
  tolerations:
  - key: dedicated
    operator: Equal      # Equal (key=value) или Exists (любое value по ключу)
    value: lab
    effect: NoSchedule
```

**Каталог системных taint'ов** (ставятся автоматически — полезно узнавать в `describe node`):

| Taint | Когда появляется | Ставит |
|-------|------------------|--------|
| `node-role.kubernetes.io/control-plane:NoSchedule` | на control-plane | kubeadm/Kubespray |
| `node.kubernetes.io/not-ready:NoExecute` | нода NotReady | node-controller |
| `node.kubernetes.io/unreachable:NoExecute` | потеряна связь с kubelet | node-controller |
| `node.kubernetes.io/memory-pressure` / `disk-pressure` / `pid-pressure` | давление ресурсов | kubelet |
| `node.kubernetes.io/unschedulable:NoSchedule` | `kubectl cordon` | kubectl |

> **Паттерн «выделенная нода» (toleration + nodeSelector ВМЕСТЕ).** toleration лишь
> РАЗРЕШАЕТ сесть на tainted-ноду, но не ведёт туда. Чтобы под ГАРАНТИРОВАННО попал
> на неё — добавляют ещё и nodeSelector/affinity на ту же ноду:
> ```yaml
> tolerations: [{ key: dedicated, operator: Equal, value: gpu, effect: NoSchedule }]
> nodeSelector: { dedicated: gpu }   # taint отгоняет ЧУЖИХ, selector ведёт СВОИХ
> ```

---

**Цель:** запретить нодой обычные поды и пустить только «толерантные».

**Ресурс:** `manifests/taints/deploy.yaml` (`taint-toleration-demo` с toleration
`dedicated=lab:NoSchedule`).

---

### 2.1 Taint отталкивает обычные поды

```bash
# (taint dedicated=lab:NoSchedule на NODE_B уже стоит из «Подготовки»)
# Обычный Pod БЕЗ toleration не сядет на NODE_B — уйдёт на NODE_A или, если
# свободных нет, в Pending. Проверим на быстром поде:
kubectl -n lab run notol --image=nginx:1.27-alpine --overrides='{"spec":{"nodeName":"'"$NODE_B"'"}}' --dry-run=client -o yaml >/dev/null
# (принудить на tainted-ноду можно только nodeName или toleration)
```

### 2.2 Toleration разрешает посадку

```bash
kubectl -n lab apply -f manifests/taints/deploy.yaml
kubectl -n lab rollout status deploy/taint-toleration-demo --timeout=120s

kubectl -n lab get pod -l app=taint-toleration-demo -o wide
# taint-toleration-demo-...   1/1   Running   <NODE>
# toleration сняла запрет — Pod допущен (в т.ч. на tainted NODE_B)
```

> Важный нюанс: toleration лишь РАЗРЕШАЕТ, но не ОБЯЗЫВАЕТ. Чтобы Pod гарантированно
> сел на выделенную ноду, toleration совмещают с `nodeSelector`/`nodeAffinity` на
> ту же ноду.

**Контрольные вопросы:**
1. Три эффекта taint (`NoSchedule`/`PreferNoSchedule`/`NoExecute`) — чем отличаются?
2. Toleration заставляет Pod сесть на tainted-ноду? Если нет — что заставит?
3. Зачем на control-plane нодах стоят taint'ы по умолчанию?

---

## Часть 3: Affinity и Anti-affinity

### Теория для изучения перед частью

- **nodeAffinity** — гибкий преемник nodeSelector. Два режима:
  `requiredDuringScheduling…` (жёстко, как nodeSelector, но с операторами
  `In/NotIn/Exists`) и `preferredDuringScheduling…` (мягко, с весом — scheduler
  старается, но сядет и без выполнения).
- **podAffinity / podAntiAffinity** — размещать Pod РЯДОМ или ПОДАЛЬШЕ от других
  подов (по их labels), в пределах `topologyKey` (нода/зона/регион).
  Классика: anti-affinity, чтобы реплики не оказались на одной ноде.

```yaml
# nodeAffinity (required) — как nodeSelector, но с операторами In/NotIn/Exists/Gt/Lt:
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - { key: disktype, operator: In, values: ["ssd", "nvme"] }   # ssd ИЛИ nvme
```

**`topologyKey` = по какому label определяется «домен» разнесения:**

```
topologyKey: kubernetes.io/hostname        -> домен = НОДА  (реплики на разные ноды)
topologyKey: topology.kubernetes.io/zone   -> домен = ЗОНА  (реплики на разные зоны)

  [zone-a:  node1  node2]      [zone-b:  node3]
   anti-affinity по hostname: репл.1->node1, репл.2->node2, репл.3->node3
   anti-affinity по zone:     не больше 1 реплики на зону (переживёт падение зоны)
```

- **`IgnoredDuringExecution`** во всех именах: правило проверяется ТОЛЬКО при
  планировании; если ноды переразметили уже после запуска — под НЕ выселяется.

---

**Цель:** понять разницу required/preferred и разнести реплики.

**Ресурс:** `manifests/affinity/deploy.yaml` (`affinity-demo`, preferred
nodeAffinity по зоне).

---

### 3.1 preferred nodeAffinity (мягкое правило)

```bash
kubectl -n lab apply -f manifests/affinity/deploy.yaml
kubectl -n lab rollout status deploy/affinity-demo --timeout=120s

kubectl -n lab get pod -l app=affinity-demo -o wide
# affinity-demo-...   1/1   Running   <любая нода>
```

> В манифесте указан `preferred` для зоны `lab-a`, которой в нашем кластере НЕТ
> (зона `us-central1-a`). Поскольку правило МЯГКОЕ, scheduler не находит
> предпочтительную ноду, но всё равно сажает Pod на любую доступную. Будь это
> `required` — Pod завис бы в `Pending`. В этом и разница.

### 3.2 podAntiAffinity — разнести реплики по нодам

```yaml
# Пример: каждая реплика на отдельной ноде (topologyKey=hostname).
# required => если нод меньше, чем реплик, лишние зависнут в Pending.
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchLabels: { app: web }
      topologyKey: kubernetes.io/hostname
```

**Контрольные вопросы:**
1. Чем `requiredDuringScheduling…` отличается от `preferredDuringScheduling…`?
2. Что задаёт `topologyKey` в pod(anti)affinity?
3. Как одним правилом гарантировать, что 2 реплики не сядут на одну ноду?

---

## Часть 4: ResourceQuota и LimitRange

### Теория для изучения перед частью

- **`requests` vs `limits` (фундамент).** `requests` — ГАРАНТИЯ: scheduler ищет
  ноду, где столько СВОБОДНО (фаза Filter), и резервирует. `limits` — ПОТОЛОК:
  cgroup не даёт превысить. Разница по ресурсам:

| | CPU (compressible) | Memory (incompressible) |
|---|--------------------|--------------------------|
| превышение `limits` | **throttle** (тормозят, под жив) | **OOMKilled** (контейнер убит, exit 137) |
| роль `requests` | сколько ядра гарантировано + база для HPA% | сколько ОЗУ гарантировано |

  QoS-класс пода зависит от requests/limits: `Guaranteed` (requests==limits) >
  `Burstable` (заданы, но не равны) > `BestEffort` (не заданы) — в таком порядке
  поды и выселяют при нехватке. (Подробнее QoS/OOM — модуль 02.)

- **ResourceQuota** ограничивает СУММАРНОЕ потребление namespace: общий
  `requests.cpu/memory`, `limits.cpu/memory`, число объектов (`pods`, `services`).
  Если новый Pod превысит квоту — он будет ОТКЛОНЁН при создании.
- **LimitRange** задаёт per-container значения по умолчанию (`defaultRequest`/
  `default`) и мин/макс. Важно: при активной ResourceQuota на requests/limits
  каждый Pod ОБЯЗАН их иметь — LimitRange проставляет их тем, кто не указал явно.

---

**Цель:** ограничить namespace и увидеть авто-подстановку дефолтов.

**Ресурсы:** `../../common/quotas/lab-resourcequota.yaml`, `lab-limitrange.yaml`.

---

### 4.1 ResourceQuota

```bash
kubectl apply -f ../../common/quotas/lab-resourcequota.yaml
kubectl -n lab get resourcequota lab-quota
# NAME        AGE   REQUEST                                          LIMIT
# lab-quota   5s    requests.cpu: .../1, requests.memory: .../1Gi    limits.cpu: .../2, limits.memory: .../2Gi

# Подробно — сколько уже занято из квоты
kubectl -n lab describe resourcequota lab-quota
# pods: 3/20, requests.cpu: 150m/1, requests.memory: 192Mi/1Gi, ...
```

### 4.2 LimitRange (дефолты для контейнеров)

```bash
kubectl apply -f ../../common/quotas/lab-limitrange.yaml
kubectl -n lab get limitrange lab-limits

# Pod БЕЗ явных resources получит дефолты из LimitRange (req 100m/128Mi, lim 300m/256Mi):
kubectl -n lab run nolimits --image=nginx:1.27-alpine
kubectl -n lab get pod nolimits -o jsonpath='{.spec.containers[0].resources}{"\n"}'
# {"limits":{"cpu":"300m","memory":"256Mi"},"requests":{"cpu":"100m","memory":"128Mi"}}
kubectl -n lab delete pod nolimits
```

> Без LimitRange этот же `kubectl run` при активной ResourceQuota упал бы с
> ошибкой `must specify requests.cpu` — квота требует явных значений, а их нет.

**Контрольные вопросы:**
1. Чем `ResourceQuota` (namespace-wide) отличается от `LimitRange` (per-container)?
2. Почему при активной ResourceQuota важен LimitRange?
3. Что вернёт API при попытке создать Pod сверх квоты по памяти?

---

## Часть 5: Troubleshooting — боевые инциденты

### Инцидент 1: Pod вечно `Pending` — нет подходящей ноды

Оформлен в `broken/scenario-01/`. Здесь — полный цикл.

**Воспроизведение:**

```bash
# nodeSelector dedicated=impossible-label, которого нет ни на одной ноде
kubectl -n lab apply -f broken/scenario-01/deploy.yaml
sleep 5
```

**Диагностика:**

```bash
kubectl -n lab get pods -l app=unschedulable-demo
# unschedulable-demo-...   0/1   Pending   0   5s

# Scheduler пишет ПОЧЕМУ — в Events
kubectl -n lab describe pod -l app=unschedulable-demo | grep -A2 FailedScheduling
# Warning  FailedScheduling  0/2 nodes are available: 2 node(s) didn't match
#          Pod's node affinity/selector.
```

**Решение:**

```bash
kubectl -n lab apply -f solutions/01-unschedulable/deploy.yaml   # nodeSelector на реальный label
kubectl -n lab rollout status deploy/unschedulable-demo --timeout=120s
```

**Профилактика:** перед использованием label в `nodeSelector` убедиться, что он
реально есть на нодах (`kubectl get nodes --show-labels`); для «желательного»
размещения брать `preferred` affinity вместо жёсткого selector.

### Инцидент 2: `Pending` из-за нехватки ресурсов

```bash
# Запросить заведомо больше, чем есть на ноде (e2-medium ~ 2 vCPU)
kubectl -n lab apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: toobig, namespace: lab }
spec:
  containers:
  - name: c
    image: nginx:1.27-alpine
    resources: { requests: { cpu: "8" } }   # 8 ядер — нет такой ноды
EOF
sleep 4
kubectl -n lab describe pod toobig | grep -A1 FailedScheduling
# Warning FailedScheduling ... 0/2 nodes are available: 2 Insufficient cpu.
kubectl -n lab delete pod toobig --ignore-not-found
```

### Инцидент 3: ResourceQuota отклоняет Pod

```bash
# При активной ResourceQuota без LimitRange Pod без requests будет отклонён:
# Error: pods "..." is forbidden: failed quota: lab-quota: must specify
#        limits.cpu, limits.memory, requests.cpu, requests.memory
# Лечение: добавить resources в манифест ИЛИ применить LimitRange (даст дефолты).
```

**Контрольные вопросы:**
1. Какие две частые причины бесконечного `Pending` вы знаете?
2. Где scheduler пишет причину отказа и как её прочитать?
3. Чем отличаются сообщения `didn't match node selector` и `Insufficient cpu`?

---

## Проверка модуля

Сначала «Подготовка нод» (label `disktype=ssd`, taint), затем разверните
манифесты и дайте подам подняться:

```bash
kubectl -n lab apply -f manifests/selectors/deploy.yaml
kubectl -n lab apply -f manifests/taints/deploy.yaml
kubectl -n lab apply -f manifests/affinity/deploy.yaml
kubectl -n lab rollout status deploy/select-by-label --timeout=120s

bash verify/verify.sh
# [OK] select-by-label scheduled on <node> (disktype=ssd)
# [OK] taint-toleration-demo scheduled on <node>
# [OK] module 06 verified
# (+ строка "[OK] node <node> has taints (toleration working)" появится ТОЛЬКО
#    если taint-toleration-demo сел именно на tainted-ноду. Toleration разрешает,
#    но не обязывает — чаще scheduler сажает на нетронутую ноду, и этой строки нет.)
```

`verify.sh` требует, чтобы три Deployment (`select-by-label`,
`taint-toleration-demo`, `affinity-demo`) были Ready, и проверяет, что
`select-by-label` сел на ноду с `disktype=ssd`. **Без «Подготовки нод» он
упадёт** (`select-by-label` зависнет в `Pending` → `[FAIL] deployment/...
not ready`). Промежуточные `require_*` молчат; `[OK]`-строки — от `ok`-вызовов.

---

## Финальная карта ресурсов модуля

| Ресурс | Механизм | Что демонстрирует |
|--------|----------|-------------------|
| `select-by-label` | nodeSelector `disktype=ssd` | жёсткое размещение по label ноды |
| `taint-toleration-demo` | toleration `dedicated=lab` | посадка на tainted-ноду |
| `affinity-demo` | preferred nodeAffinity | мягкое правило (садится даже при невыполнении) |
| `lab-quota` | ResourceQuota | лимит суммарных ресурсов namespace |
| `lab-limits` | LimitRange | дефолтные requests/limits контейнеров |

---

## Теоретические вопросы (итоговые)

### Блок 1: Scheduler и nodeSelector
1. Опишите фильтрацию и ранжирование в работе scheduler.
2. Когда `nodeSelector` достаточно, а когда нужна `affinity`?

### Блок 2: Taints/Tolerations
3. Чем `NoSchedule` отличается от `NoExecute`?
4. Toleration гарантирует посадку на нужную ноду? Чем это дополняют?

### Блок 3: Affinity
5. required vs preferred affinity — последствия для `Pending`.
6. Как `podAntiAffinity` + `topologyKey` разносят реплики по отказоустойчивым доменам?

### Блок 4: Quotas
7. Что произойдёт при попытке превысить `ResourceQuota`?
8. Почему `LimitRange` нужен рядом с `ResourceQuota`?

---

## Практические задания (отработка)

> Делайте на живом кластере; проверяйте себя командами и `verify/verify.sh`.

1. Разметьте worker-ноду, посадите под `nodeSelector`; снимите метку — убедитесь, что под уходит в `Pending`.
2. Навесьте `taint NoSchedule`; покажите, что обычный под не садится, а с `toleration` — садится.
3. Соберите `podAntiAffinity required` на `hostname` — на 2 нодах 3-я реплика повиснет `Pending`; смягчите до `preferred`.
4. Примените `ResourceQuota` без `LimitRange` и поймайте отказ `must specify requests`; добавьте `LimitRange`.
5. Сделайте под, который не влезает по CPU, и прочитайте точную причину в `FailedScheduling`.

---

## Шпаргалка

```bash
# === Labels / nodeSelector ===
kubectl get nodes --show-labels
kubectl label node <node> disktype=ssd --overwrite
kubectl label node <node> disktype-                     # снять label
kubectl -n lab get pod -l app=select-by-label -o wide   # на какой ноде

# === Taints / Tolerations ===
kubectl taint nodes <node> dedicated=lab:NoSchedule --overwrite
kubectl taint nodes <node> dedicated=lab:NoSchedule-    # снять taint
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.taints}{"\n"}{end}'

# === Affinity (диагностика) ===
kubectl -n lab describe pod <p> | grep -A5 "Node-Selectors\|Tolerations"

# === Quotas ===
kubectl -n lab describe resourcequota lab-quota          # used/hard
kubectl -n lab get limitrange lab-limits -o yaml

# === Почему Pending ===
kubectl -n lab describe pod <p> | grep -A2 FailedScheduling
kubectl -n lab get events --field-selector reason=FailedScheduling
```

---

## Уборка

Обязательно снимите разметку нод — иначе она повлияет на следующие модули:

```bash
kubectl label node "$NODE_A" disktype-                        # снять label
kubectl taint nodes "$NODE_B" dedicated=lab:NoSchedule-       # снять taint
kubectl -n lab delete resourcequota lab-quota --ignore-not-found
kubectl -n lab delete limitrange lab-limits --ignore-not-found
kubectl -n lab delete -k manifests/
```
