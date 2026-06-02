# Лабораторная работа 13: Отказоустойчивость (topologySpread, anti-affinity, PDB)

Цель: научиться размещать рабочие нагрузки так, чтобы падение одной ноды (или
зоны) не уносило весь сервис, и защищать доступность во время планового
обслуживания. К концу модуля вы равномерно «размазываете» реплики по нодам и
понимаете, почему часть подов может застрять в `Pending`.

> Модуль требует **multi-node** кластер (у нас 3 ноды Kubespray) — на одной ноде
> распределять нечего.

---

## Предварительные требования

```bash
kubectl -n lab delete deploy,pdb,pod --all --ignore-not-found 2>/dev/null
kubectl create ns lab --dry-run=client -o yaml | kubectl apply -f -
kubectl get nodes --no-headers | wc -l    # сколько нод (нужно >=2)
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

- **PDB** защищает от ДОБРОВОЛЬНЫХ disruption (drain ноды на обслуживание,
  обновление): `minAvailable` / `maxUnavailable`. Eviction, нарушающий PDB,
  отклоняется Eviction API.
- `ALLOWED DISRUPTIONS = replicas − minAvailable` — сколько подов можно увести
  одновременно.
- PDB НЕ защищает от НЕдобровольных сбоев (падение ноды) — только от плановых
  операций.

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
kubectl -n lab apply -f manifests/
kubectl -n lab rollout status deploy/resilient-app --timeout=120s

bash verify/verify.sh
# [OK] resilient-app spread across 3 nodes
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

1. Чем topologySpread отличается от podAntiAffinity по смыслу?
2. Что задают `maxSkew`/`topologyKey`/`whenUnsatisfiable`?
3. Как считается `ALLOWED DISRUPTIONS` и от чего PDB защищает?
4. Почему `required` anti-affinity при репликах > нод даёт `Pending`?
5. Как spread + PDB вместе обеспечивают обслуживание без простоя?

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
