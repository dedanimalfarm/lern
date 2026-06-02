# Лабораторная работа 08: Наблюдаемость (events, conditions, logs, metrics)

Цель: диагностировать деградации только средствами кластера — по событиям,
условиям, логам и базовым метрикам, без внешнего стека. К концу модуля вы
собираете линейный runbook инцидента и отличаете проблему приложения от
проблемы кластера.

---

## Предварительные требования

```bash
kubectl -n lab delete deploy,sts,ds,job,cronjob,svc,pvc,pod,ingress,netpol,cm,secret --all --ignore-not-found 2>/dev/null
kubectl create ns lab --dry-run=client -o yaml | kubectl apply -f -
```

---

## Стартовая проверка

```bash
# metrics-server нужен для `kubectl top` (Часть 3). На GKE он есть по умолчанию;
# на kind/minikube — ставится отдельно.
kubectl top nodes 2>/dev/null && echo "metrics-server: OK" || echo "metrics-server НЕ установлен — Часть 3 не отработает"
```

---

## Часть 1: Events и Conditions

### Теория для изучения перед частью

- **Events** — хронология того, что делал кластер с объектом (Scheduled,
  Pulled, Started, FailedScheduling, BackOff). Живут ~1 час, потом исчезают.
- **Conditions** — агрегированное текущее состояние ресурса (`Ready`,
  `Available`, `Progressing`) с `status`/`reason`/`message`. Это «итог», а
  events — «история».

---

**Цель:** собрать таймлайн и текущее состояние demo-нагрузки.

**Ресурс:** `manifests/demo/deploy.yaml` (`obs-demo`, пишет структурированный лог).

---

### 1.1 Events и Conditions

```bash
kubectl -n lab apply -f manifests/demo/deploy.yaml
kubectl -n lab rollout status deploy/obs-demo --timeout=120s

# Conditions Deployment — агрегированное состояние
kubectl -n lab get deploy obs-demo -o jsonpath='{range .status.conditions[*]}{.type}={.status} ({.reason}){"\n"}{end}'
# Available=True (MinimumReplicasAvailable)
# Progressing=True (NewReplicaSetAvailable)

# Events пода — хронология (в хвосте describe)
kubectl -n lab describe pod -l app=obs-demo | sed -n '/Events:/,$p'
# Scheduled -> Pulled -> Created -> Started
```

**Контрольные вопросы:**
1. Чем `Events` отличаются от `Conditions`?
2. Почему events нельзя считать долговременным логом?
3. Что означает `Available=True` у Deployment?

---

## Часть 2: Логи

### Теория для изучения перед частью

- `kubectl logs` читает stdout/stderr контейнера. Полезные флаги: `--previous`
  (логи упавшего запуска), `-c <container>` (нужный контейнер), `--since`/`--tail`,
  `-f` (поток), `-l <selector>` (по подам).
- **Структурированные логи** (`key=value` или JSON) машинно-разбираемы — проще
  фильтровать и агрегировать.

---

**Цель:** прочитать логи, в т.ч. упавшего контейнера.

---

### 2.1 Структурированные логи

```bash
kubectl -n lab logs deploy/obs-demo --tail=3
# ts=2026-06-02T...:00+00:00 level=info msg=heartbeat
# ts=2026-06-02T...:05+00:00 level=info msg=heartbeat

# Фильтрация по полю (плюс structured logging):
kubectl -n lab logs deploy/obs-demo --tail=20 | grep 'level=info'
```

### 2.2 Логи упавшего контейнера

```bash
# Для CrashLoop-пода обычный logs покажет НОВЫЙ запуск — нужен --previous:
# kubectl -n lab logs <pod> --previous
# (демонстрация — в Части 4, инцидент CrashLoopBackOff)
```

**Контрольные вопросы:**
1. Зачем `--previous` и когда обычный `logs` бесполезен?
2. Почему структурированные логи упрощают расследование?
3. Как прочитать логи конкретного контейнера в многоконтейнерном поде?

---

## Часть 3: Метрики (metrics-server, kubectl top)

### Теория для изучения перед частью

- **metrics-server** собирает CPU/RAM подов и нод и отдаёт их `kubectl top` и
  HPA. Это «здесь и сейчас», БЕЗ истории.
- Для истории/алертов/дашбордов нужен Prometheus + Grafana — metrics-server их не
  заменяет.

---

**Цель:** снять текущую нагрузку.

---

### 3.1 kubectl top

```bash
kubectl top nodes
# NAME        CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
# ...-b02f    120m         6%     780Mi           27%

kubectl top pods -n lab
# NAME            CPU(cores)   MEMORY(bytes)
# obs-demo-...    1m           2Mi
```

> Сразу после старта пода возможно `metrics not available yet` — metrics-server
> собирает данные с задержкой ~1-2 мин, просто подождите. Ошибка `Metrics API
> not available` (без "yet") означает, что metrics-server не установлен (типично
> для свежего kind); на GKE он есть из коробки.

**Контрольные вопросы:**
1. Что даёт `metrics-server` и чего он принципиально НЕ умеет?
2. Чем `kubectl top` отличается от `kubectl describe node` (Allocated resources)?
3. Зачем metrics-server нужен для HPA?

---

## Часть 4: Troubleshooting и runbook

### Инцидент 1: `CrashLoopBackOff`

Оформлен в `broken/scenario-01/`. Здесь — полный цикл.

**Воспроизведение:**

```bash
# Команда контейнера завершается с exit 1 сразу после старта
kubectl -n lab apply -f broken/scenario-01/deploy.yaml
sleep 15
```

**Диагностика:**

```bash
kubectl -n lab get pod -l app=obs-broken
# obs-broken-...   0/1   CrashLoopBackOff   3 (20s ago)   45s
#                  ^ растущий back-off между рестартами

# Логи последнего УПАВШЕГО запуска. ВАЖНО: для очень короткого контейнера
# (echo+exit за <1с) логи могут не успеть сохраниться — тогда будет
# 'unable to retrieve container logs', и причину надёжнее брать из lastState ниже.
kubectl -n lab logs -l app=obs-broken --previous --tail=2
# fail        (либо 'unable to retrieve...' если контейнер жил доли секунды)

# Код и причина завершения
kubectl -n lab get pod -l app=obs-broken \
  -o jsonpath='{.items[0].status.containerStatuses[0].lastState.terminated.reason}{" exit="}{.items[0].status.containerStatuses[0].lastState.terminated.exitCode}{"\n"}'
# Error exit=1
```

**Решение:**

```bash
kubectl -n lab apply -f solutions/01-crashloop/deploy.yaml
kubectl -n lab rollout status deploy/obs-broken --timeout=120s
```

**Профилактика:** PID 1 контейнера должен быть долгоживущим процессом; алёрт на
`RESTARTS > 0` и на `reason=CrashLoopBackOff`.

### Бонус: линейный runbook деградации

```bash
# 1) Что не так и с каких пор
kubectl -n lab get pods -o wide
kubectl -n lab get events --sort-by=.lastTimestamp | tail -15
# 2) Почему (состояние и причина)
kubectl -n lab describe pod <pod>
# 3) Что говорит приложение
kubectl -n lab logs <pod> [--previous]
# 4) Ресурсы (давление?)
kubectl top nodes && kubectl top pods -n lab
# 5) Сеть (если сервис)
kubectl -n lab get svc,endpoints,ingress
```

**Контрольные вопросы:**
1. Что такое `CrashLoopBackOff` и как растёт интервал рестартов?
2. Почему при CrashLoop нужен `--previous`?
3. Опишите порядок шагов runbook и зачем он линеен.

---

## Проверка модуля

```bash
kubectl -n lab apply -f manifests/demo/deploy.yaml
kubectl -n lab rollout status deploy/obs-demo --timeout=120s

bash verify/verify.sh
# [OK] obs-demo logs are structured (contain 'level=')
# [OK] module 08 verified
```

`verify.sh` проверяет: namespace `lab` → `Deployment/obs-demo` готов → у пода
есть логи → логи структурированы (содержат `level=`). Две `[OK]`-строки от
`ok`-вызовов; промежуточные проверки молчат.

---

## Финальная карта ресурсов модуля

| Ресурс | Что демонстрирует |
|--------|-------------------|
| `obs-demo` | структурированные логи, events/conditions, метрики |
| `obs-broken` | CrashLoopBackOff, `logs --previous`, lastState |

---

## Теоретические вопросы (итоговые)

1. Сопоставьте сигналы: events / conditions / logs / metrics — что даёт каждый?
2. Почему для диагностики нужны все четыре, а не один?
3. Чем `metrics-server` ограничен против Prometheus?
4. Как отличить проблему приложения от проблемы ноды/кластера?
5. Зачем нужен runbook и как он снижает MTTR?

---

## Шпаргалка

```bash
# === Events / Conditions ===
kubectl -n lab get events --sort-by=.lastTimestamp | tail -20
kubectl -n lab describe pod <p> | sed -n '/Events:/,$p'
kubectl -n lab get deploy <d> -o jsonpath='{.status.conditions}'

# === Логи ===
kubectl -n lab logs deploy/<d> --tail=50 -f
kubectl -n lab logs <pod> --previous            # упавший запуск
kubectl -n lab logs <pod> -c <container>        # нужный контейнер

# === Метрики ===
kubectl top nodes
kubectl top pods -n lab

# === Причина рестарта ===
kubectl -n lab get pod <p> -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}'

# === Уборка ===
kubectl -n lab delete -k manifests/ ; kubectl -n lab delete deploy obs-broken --ignore-not-found
```

---

## Уборка

```bash
kubectl -n lab delete -k manifests/
kubectl -n lab delete deploy obs-broken --ignore-not-found
```
