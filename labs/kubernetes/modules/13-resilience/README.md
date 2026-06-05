# Лабораторная работа 13: Отказоустойчивость (topologySpread, anti-affinity, PDB)

> ⏱ время ~20 мин · сложность 3/5 · пререквизиты: Трек 1 (Core)

Цель: научиться размещать рабочие нагрузки так, чтобы падение одной ноды (или
зоны) не уносило весь сервис, и защищать доступность во время планового
обслуживания. К концу модуля вы равномерно «размазываете» реплики по нодам и
понимаете, почему часть подов может застрять в `Pending`.

> Модуль требует **multi-node** кластер (у нас 3 ноды Kubespray) — на одной ноде
> распределять нечего.

---

## Предварительные требования

```bash
# kubeconfig нашего кластера (Kubespray); на другом стенде — свой путь/контекст
export KUBECONFIG=/root/.kube/kubespray.conf
kubectl -n lab delete deploy,pdb,pod --all --ignore-not-found 2>/dev/null
kubectl create ns lab --dry-run=client -o yaml | kubectl apply -f -
kubectl get nodes --no-headers | wc -l    # сколько нод (нужно >=2)
```

## Стартовая проверка

Убедитесь, что кластер доступен:
```bash
kubectl get nodes
```

---

## Часть 1: topologySpreadConstraints

### Теория для изучения перед частью

- **topologySpread** требует РАВНОМЕРНОГО распределения подов по «доменам»
  (`topologyKey`: `kubernetes.io/hostname` = ноды, `topology.kubernetes.io/zone`
  = зоны).
- **`maxSkew`** — максимально допустимая разница числа подов между доменами.
- **`whenUnsatisfiable`**: `DoNotSchedule` (жёстко — иначе `Pending`) или
  `ScheduleAnyway` (мягко — постарается, но посадит).

**`skew` на числах** (maxSkew=1, домены = ноды; у нас 2 worker, cp таинтнут):

| Подов | Раскладка | skew = max−min | DoNotSchedule пускает? |
|:---:|:---:|:---:|:---|
| 1 | w1=1, w2=0 | 1 | да (≤1) |
| 2 | w1=1, w2=1 | 0 | да (балансир) |
| 3 | w1=2, w2=1 | 1 | да (3-й только на МЕНЬШИЙ домен) |
| 4 | w1=2, w2=2 | 0 | да |

> `skew = (макс. подов в домене) − (мин. подов в домене)`. Новый под при
> `DoNotSchedule` сядет ТОЛЬКО туда, где итоговый skew ≤ `maxSkew`. Если все домены
> равны и нельзя добавить без нарушения — под `Pending`.

- **⚠️ `nodeTaintsPolicy` (критично на Kubespray!).** Какие ноды считать доменами:
  `Ignore` (ПО УМОЛЧАНИЮ) — taint'ы игнорируются → таинтнутая control-plane нода
  ВХОДИТ в домены как «домен с 0 подов» → ломает skew → лишние `Pending`. `Honor` —
  исключить ноды с непротолерированными taint'ами из расчёта. На нашем кластере (cp
  с taint) в `app.yaml` стоит **`nodeTaintsPolicy: Honor`** — иначе spread по 2
  worker сломался бы. Парный `nodeAffinityPolicy` (default `Honor`) — учитывать ли
  nodeSelector/affinity при выборе доменов.
- **`minDomains`** — требовать МИНИМУМ N непустых доменов (защита «а если живой только
  1 домен — не лепи всё туда»).

**topologySpread vs podAntiAffinity** (часто путают):

| | topologySpread | podAntiAffinity |
|---|---|---|
| Цель | РАВНОМЕРНО (skew по доменам) | НЕ ВМЕСТЕ (расталкивать) |
| Гранулярность | счёт по доменам (мягко/жёстко) | бинарно: можно/нельзя в домене |
| Масштаб | дёшев на 1000+ нод | дорог (O(подов²) при required) |
| Комбинируют | да — spread для баланса + antiAffinity для строгого «не на одной ноде» | |

---

**Цель:** размазать 3 реплики по 3 нодам.

**Ресурс:** `manifests/app.yaml` (`resilient-app`, spread + anti-affinity).

---

### 1.1 Равномерное распределение

```bash
kubectl -n lab apply -f manifests/app.yaml
kubectl -n lab rollout status deploy/resilient-app --timeout=120s

# по одной реплике на каждую ноду (maxSkew=1):
kubectl -n lab get pods -l app=resilient-app \
  -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName
# resilient-app-...-a   ...-node1
# resilient-app-...-b   ...-node2
# resilient-app-...-c   ...-node3
```

**Контрольные вопросы:**
1. Что задаёт `topologyKey` и чем нода отличается от зоны как домен?
2. Что означает `maxSkew: 1`?
3. Разница `DoNotSchedule` и `ScheduleAnyway`?

---

## Часть 2: podAntiAffinity

### Теория для изучения перед частью

- **podAntiAffinity** — «не сажай рядом»: реплики одного приложения на РАЗНЫЕ
  ноды. `required...` (жёстко) / `preferred...` (мягко, с весом).
- Отличие от topologySpread: anti-affinity про «не вместе», spread про
  «равномерно». Часто комбинируют для надёжности.

```yaml
# required: реплики ОБЯЗАНЫ на разных хостах (нод < реплик -> лишние Pending)
podAntiAffinity:
  requiredDuringSchedulingIgnoredDuringExecution:
  - labelSelector: { matchLabels: { app: resilient-app } }
    topologyKey: kubernetes.io/hostname        # «домен» = нода
# preferred: ПРЕДПОЧтительно на разных (под всё равно сядет; weight 1..100 — приоритет)
  preferredDuringSchedulingIgnoredDuringExecution:
  - weight: 100
    podAffinityTerm:
      labelSelector: { matchLabels: { app: resilient-app } }
      topologyKey: kubernetes.io/hostname
```

- **`topologyKey`** определяет «домен совместности»: `hostname` — не на одной НОДЕ;
  `zone` — не в одной ЗОНЕ (переживает падение зоны). Anti-affinity «расталкивает»
  в пределах этого домена.
- **`weight` (preferred).** scheduler складывает веса всех выполненных preferred-правил
  в score ноды и выбирает ноду с наибольшим — то есть preferred влияет на ВЫБОР,
  но не блокирует посадку (в отличие от required).
- **Масштаб:** `required` antiAffinity дорог (проверка пар подов) — на больших
  деплоях берут topologySpread, а antiAffinity оставляют для критичного «строго не
  на одной ноде».

---

### 2.1 Реплики на разных нодах

```bash
# В manifests/app.yaml задан preferred podAntiAffinity по hostname —
# поэтому реплики «расталкиваются» по нодам (в дополнение к spread).
kubectl -n lab get pods -l app=resilient-app -o wide | awk '{print $1, $7}'
```

> `required` anti-affinity при репликах > нод оставит лишние `Pending` (нет
> «разных» нод). `preferred` — лишь предпочтение, под всё равно сядет.

**Контрольные вопросы:**
1. Чем `required` отличается от `preferred` podAntiAffinity по последствиям?
2. Когда anti-affinity, а когда topologySpread?
3. Что будет с `required` anti-affinity, если реплик больше, чем нод?

---

## Часть 3: PodDisruptionBudget

### Теория для изучения перед частью

- **Voluntary vs involuntary disruptions (фундамент PDB).**
  *Voluntary* (добровольные) — то, что инициирует человек/контроллер: `drain`,
  обновление ноды, удаление пода через **Eviction API**. *Involuntary* —
  падение ноды, kernel panic, OOM, вытеснение по нехватке ресурсов.
  **PDB защищает ТОЛЬКО от voluntary** (через Eviction API). От падения ноды PDB не
  спасёт — для этого нужны spread/antiAffinity (несколько реплик на разных нодах).
- **PDB** (`minAvailable` / `maxUnavailable`): минимум живых / максимум недоступных
  реплик во время voluntary-операций.

| Поле | `ALLOWED DISRUPTIONS` (replicas=3) |
|------|------------------------------------|
| `minAvailable: 2` | `3 − 2 = 1` |
| `minAvailable: 50%` | `3 − ceil(1.5)=2 → 1` |
| `maxUnavailable: 1` | `1` (напрямую) |
| `minAvailable: 3` | `0` — нода НЕДРЕНИРУЕМА (drain виснет) |

**Поток Eviction API (что делает `kubectl drain` под капотом):**

```
drain -> для каждого пода: POST /eviction
            apiserver проверяет PDB:
              ALLOWED DISRUPTIONS > 0 ?
                да  -> 201 Created (под выселен, ALLOWED уменьшается)
                нет -> 429 Too Many Requests -> drain ЖДЁТ и повторяет
            (контроллер пересоздаёт под на другой ноде -> ALLOWED восстанавливается)
```

- **`unhealthyPodEvictionPolicy` (k8s 1.26+).** `IfHealthyBudget` (по умолчанию) —
  нездоровые (не Ready) поды защищены PDB так же → могут заблокировать drain, даже
  если они «мёртвый груз». `AlwaysAllow` — нездоровые поды выселяются всегда (не
  считаются в budget) — обычно правильнее для обслуживания.
- **PDB × HPA.** PDB считает от ТЕКУЩего числа подов, не от `replicas` Deployment.
  Если HPA скейлит вниз во время drain — `ALLOWED` может неожиданно стать 0.

---

**Цель:** ограничить одновременные выселения.

**Ресурс:** `manifests/pdb.yaml` (`minAvailable: 2`).

---

### 3.1 PDB и drain

```bash
kubectl -n lab apply -f manifests/pdb.yaml
kubectl -n lab get pdb resilient-app-pdb
# NAME                MIN AVAILABLE   ALLOWED DISRUPTIONS
# resilient-app-pdb   2               1               <- из 3 можно увести 1

# Пробный drain (server dry-run) уважает PDB:
NODE=$(kubectl -n lab get pods -l app=resilient-app -o jsonpath='{.items[0].spec.nodeName}')
kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data --dry-run=server 2>&1 | head -3
```

**Контрольные вопросы:**
1. Как считается `ALLOWED DISRUPTIONS`?
2. От каких disruption PDB защищает, а от каких — нет?
3. Что произойдёт с `drain`, если PDB не позволяет увести ни одного пода?

### 3.2 Обслуживание ноды: cordon → drain → uncordon

Реальный сценарий планового обслуживания: сначала ЗАПРЕТИТЬ планирование новых
подов на ноду (`cordon`), затем ВЫГНАТЬ существующие (`drain`) — Kubernetes
переселит реплики на другие ноды, уважая PDB. Сервис не падает, потому что
реплики заранее на разных нодах (spread/anti-affinity), а PDB ограничивает темп.

```bash
NODE=$(kubectl -n lab get pods -l app=resilient-app -o jsonpath='{.items[0].spec.nodeName}')

# 1) cordon — нода больше НЕ принимает новые поды (текущие пока работают)
kubectl cordon "$NODE"
kubectl get node "$NODE"        # STATUS: Ready,SchedulingDisabled

# 2) drain — выгнать поды с ноды. PDB не даст увести больше ALLOWED за раз;
#    реплики пересоздаются на других нодах.
kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data
kubectl -n lab get pods -l app=resilient-app -o wide   # ни одного пода на $NODE

# 3) uncordon — вернуть ноду в планирование после обслуживания
kubectl uncordon "$NODE"
```

> Последовательность строго `cordon → drain → (обслуживание) → uncordon`. `drain`
> сам делает `cordon` неявно, но явный `cordon` заранее останавливает приток
> новых подов на ноду, которую вы готовитесь выводить.

---

## Часть 4: Troubleshooting

### Инцидент 1: реплика `Pending` из-за required anti-affinity

Разобран в `broken/scenario-01/`: 3 реплики + `required` podAntiAffinity по
hostname на 2 доступных worker-нодах → 2 Running + 1 Pending (3-й «разной» ноды
нет). Диагностика — `describe pod` → `FailedScheduling ... didn't match pod
anti-affinity rules`. Решение — `preferred` вместо `required`, либо добавить ноды.

> **Нюанс среды (поймано на Kubespray):** control-plane нода `k8s-cp-1` имеет
> taint, поэтому доступных для нагрузки нод — 2 (worker). Для `topologySpread`
> это важно: с `nodeTaintsPolicy: Ignore` (по умолчанию) недоступная нода
> считается доменом с 0 подов и ломает skew → лишние `Pending`. В `manifests/app.yaml`
> стоит `nodeTaintsPolicy: Honor` — учитывать только реально доступные ноды.

### Инцидент 2: PDB делает ноду недренируемой

```bash
# Если minAvailable == replicas, ALLOWED DISRUPTIONS = 0 -> drain зависнет:
# kubectl drain <node> ... -> "Cannot evict pod as it would violate PDB"
# Лечение: minAvailable < replicas (или maxUnavailable >= 1) и держать >=2 реплик.
```

**Контрольные вопросы:**
1. `FailedScheduling ... topology spread constraints` — что менять?
2. Почему одиночная реплика + `minAvailable: 1` блокирует drain?
3. Как сочетание spread + PDB даёт zero-downtime обслуживание?

---

## Проверка модуля

```bash
kubectl -n lab apply -k manifests/      # -k (kustomize): в каталоге есть kustomization.yaml
kubectl -n lab rollout status deploy/resilient-app --timeout=120s

bash verify/verify.sh
# [OK] resilient-app spread across 2 nodes   (у нас 2 worker-ноды; cp таинтнут)
# [OK] module 13 verified
```

`verify.sh`: namespace `lab` → `resilient-app` готов → есть PDB → реплики
распределены минимум на 2 ноды.

---

## Финальная карта ресурсов модуля

| Ресурс | Механизм | Что демонстрирует |
|--------|----------|-------------------|
| `resilient-app` | topologySpread + antiAffinity | равномерное распределение по нодам |
| `resilient-app-pdb` | PodDisruptionBudget | защита доступности при drain |
| broken (5 реплик) | DoNotSchedule | Pending при невозможности равномерности |

---

## Теоретические вопросы (итоговые)

1. Чем topologySpread отличается от podAntiAffinity по смыслу и масштабируемости?
2. Что задают `maxSkew`/`topologyKey`/`whenUnsatisfiable`? Посчитайте skew для 3 подов на 2 домена.
3. Зачем `nodeTaintsPolicy: Honor` на Kubespray и что сломается при дефолтном `Ignore`?
4. Voluntary vs involuntary disruption — от каких PDB защищает, а от каких нет?
5. Как считается `ALLOWED DISRUPTIONS` (для `minAvailable` и `maxUnavailable`)? Опишите поток Eviction API (429/201).
6. Что делает `unhealthyPodEvictionPolicy: AlwaysAllow` и зачем?
7. Почему `required` anti-affinity при репликах > нод даёт `Pending`?

---

## Практические задания (отработка)

> Делайте на живом кластере; проверяйте себя командами и `verify/verify.sh`.

1. Разверните приложение с `topologySpreadConstraints` и убедитесь, что реплики на РАЗНЫХ нодах.
2. Воспроизведите `Pending` с `requiredDuringScheduling` antiAffinity на 2 нодах; смягчите до `preferred`.
3. Создайте PDB и посчитайте `ALLOWED DISRUPTIONS`; сделайте `drain` и убедитесь, что PDB защищает доступность.
4. Сравните `minAvailable` и `maxUnavailable` в PDB на одном приложении.
5. Симулируйте «потерю ноды» (cordon+drain) и проследите, что сервис не упал.

---

## Шпаргалка

```bash
# === Распределение ===
kubectl -n lab get pods -l app=resilient-app -o wide
kubectl -n lab get pods -l app=resilient-app -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName
kubectl -n lab describe pod -l app=resilient-app | grep -A2 "Topology Spread\|FailedScheduling"

# === PDB ===
kubectl -n lab get pdb
kubectl -n lab describe pdb resilient-app-pdb
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data --dry-run=server

# === Уборка ===
kubectl -n lab delete -k manifests/
```

---

## Уборка

```bash
kubectl -n lab delete -k manifests/
```
