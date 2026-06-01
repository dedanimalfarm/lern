# Лабораторная работа 02: Жизненный цикл Pod (initContainers, probes, QoS/OOM)

Цель: разобраться, что происходит с Pod от создания до завершения — фазы и
состояния контейнеров, init-контейнеры, три типа проб (`readiness`/`liveness`/
`startup`), а также как `requests`/`limits` задают QoS-класс и приводят к
`OOMKilled`. К концу модуля вы по симптомам отличаете «не готов к трафику» от
«надо перезапустить» и воспроизводите/чините оба класса инцидентов.

---

## Предварительные требования

```bash
# 1) Кластер, который реально запускает контейнеры (kind/minikube/k3s/GKE).
#    На kwok-эмуляторе пробы и OOM не отработают — нужен настоящий kubelet.
kubectl version --output=yaml | head -5

# 2) Namespace lab (создаётся идемпотентно)
kubectl create ns lab --dry-run=client -o yaml | kubectl apply -f -

# 3) Метрики по подам (kubectl top) — опционально, если установлен metrics-server
kubectl top pods -n kube-system 2>/dev/null | head -3 || echo "metrics-server не обязателен"
```

> Все «ожидаемые выводы» приведены для типового кластера. Имена нод, IP подов и
> точные тайминги у вас будут другими — важна суть (фазы, статусы, причины).

---

## Стартовая проверка

```bash
# Пусто ли в namespace перед началом
kubectl -n lab get pods,deploy,svc
# No resources found in lab namespace.

# Готовность DNS кластера — на него опирается init-контейнер из Части 2
kubectl -n kube-system get deploy -l k8s-app=kube-dns
# NAME      READY   UP-TO-DATE   AVAILABLE
# coredns   2/2     2            2
```

---

## Часть 1: Фазы Pod и состояния контейнеров

### Теория для изучения перед частью

- **Фаза Pod** (`.status.phase`) — высокоуровневое состояние: `Pending`
  (принят, но контейнеры ещё не запущены — тянется образ, ждёт расписания/тома),
  `Running` (хотя бы один контейнер запущен), `Succeeded`/`Failed`
  (все контейнеры завершились), `Unknown`.
- **Состояние контейнера** (`.status.containerStatuses[].state`) — точнее фазы:
  `Waiting` (с `reason`: `ContainerCreating`, `CrashLoopBackOff`,
  `ImagePullBackOff`), `Running`, `Terminated` (с `reason`: `Completed`, `Error`,
  `OOMKilled` и `exitCode`).
- **`Running` ≠ `Ready`.** Колонка `READY n/m` считает контейнеры, прошедшие
  `readinessProbe`. Фаза может быть `Running`, а `READY 0/1`.
- **`restartPolicy`** (`Always`/`OnFailure`/`Never`): для Deployment всегда
  `Always`; у разовых Pod/Job — `OnFailure`/`Never`. Определяет, перезапустит ли
  kubelet завершившийся контейнер.
- **Завершение (graceful shutdown):** при удалении Pod kubelet шлёт контейнеру
  `SIGTERM`, ждёт `terminationGracePeriodSeconds` (по умолчанию 30с) и лишь потом
  `SIGKILL`. Перед SIGTERM выполняется `preStop`-hook. `postStart`/`preStop` —
  это lifecycle-hooks контейнера (точки вмешательства в начале и конце жизни).

---

**Цель:** научиться читать фазу Pod и состояние контейнера и понимать разницу
между ними.

---

### 1.1 Наблюдение фаз на лету

```bash
# Запустим короткоживущий Pod и проследим фазы (Ctrl+C для выхода)
kubectl -n lab run phase-demo --image=busybox:1.36 --restart=Never -- \
  sh -c 'echo working; sleep 5; echo done'
kubectl -n lab get pod phase-demo -w
# NAME         READY   STATUS              RESTARTS   AGE
# phase-demo   0/1     ContainerCreating   0          1s    <- образ тянется
# phase-demo   1/1     Running             0          3s    <- контейнер пошёл
# phase-demo   0/1     Completed           0          9s    <- команда завершилась успехом
```

```bash
# Фаза и состояние контейнера точечно
kubectl -n lab get pod phase-demo -o jsonpath='{.status.phase}{"\n"}'
# Succeeded

kubectl -n lab get pod phase-demo \
  -o jsonpath='{.status.containerStatuses[0].state.terminated.reason}{"\n"}'
# Completed

kubectl -n lab delete pod phase-demo
```

> `restartPolicy: Never` + успешное завершение ⇒ фаза `Succeeded`, контейнер
> `Terminated/Completed`. С `OnFailure` упавший контейнер был бы перезапущен.

### 1.2 Состояние Waiting и его reason

```bash
# Заведомо несуществующий образ — увидим Waiting с понятным reason
kubectl -n lab run bad-image --image=nginx:nope-not-real --restart=Never
sleep 6
kubectl -n lab get pod bad-image
# NAME        READY   STATUS         RESTARTS   AGE
# bad-image   0/1     ErrImagePull   0          6s

kubectl -n lab get pod bad-image \
  -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}{"\n"}'
# ImagePullBackOff

kubectl -n lab delete pod bad-image --force --grace-period=0 2>/dev/null
```

### 1.3 Завершение Pod: graceful shutdown

Удаление Pod — не мгновенное убийство, а последовательность:

1. Pod помечается `Terminating`, его IP **сразу** убирается из `Endpoints`
   (новый трафик не идёт).
2. Выполняется `preStop`-hook (если задан) — например, дать балансировщику увести
   соединения.
3. Контейнеру шлётся `SIGTERM` — шанс корректно закрыть коннекты и сбросить буферы.
4. Ожидание `terminationGracePeriodSeconds` (по умолчанию 30с).
5. Не завершился — `SIGKILL` (принудительно).

```bash
# nginx корректно обрабатывает SIGTERM -> выходит быстро, не ждёт все 30с
kubectl -n lab run term-demo --image=nginx:1.27-alpine
kubectl -n lab wait --for=condition=Ready pod/term-demo --timeout=60s
time kubectl -n lab delete pod term-demo
# real ~1-2s   <- быстрый graceful exit; приложение, игнорящее SIGTERM, ждало бы 30с

# Принудительно, без grace (только если под завис):
# kubectl -n lab delete pod <p> --grace-period=0 --force
```

```yaml
# Как заложить graceful shutdown в манифест:
spec:
  terminationGracePeriodSeconds: 30
  containers:
  - name: app
    lifecycle:
      preStop:
        exec: { command: ["sh", "-c", "sleep 5"] }   # дать LB увести трафик до SIGTERM
```

> preStop + корректная обработка SIGTERM = деплой без обрыва запросов. Если
> приложение игнорирует SIGTERM, оно жёстко убивается по истечении grace period,
> рвя активные соединения.

**Контрольные вопросы:**
1. Чем фаза Pod (`.status.phase`) отличается от состояния контейнера
   (`.status.containerStatuses[].state`)?
2. Pod в фазе `Running`, но `READY 0/1`. Что это значит?
3. Какие три значения принимает `restartPolicy` и для каких типов нагрузки
   каждое уместно?
4. В каком состоянии (`Waiting`/`Running`/`Terminated`) и с каким `reason`
   окажется контейнер при опечатке в имени образа?
5. Опишите шаги graceful shutdown при удалении Pod. За что отвечают
   `terminationGracePeriodSeconds` и `preStop`-hook?

---

## Часть 2: Init-контейнеры

### Теория для изучения перед частью

- **initContainers запускаются последовательно** до основных контейнеров и
  должны успешно завершиться (`Completed`). Если init падает — Pod не пойдёт
  дальше, kubelet перезапускает init по `restartPolicy`.
- **Назначение:** дождаться зависимости (БД, DNS, миграции), подготовить данные
  в общем томе, выставить права — то, что должно произойти ДО старта приложения.
- **Отличие от sidecar:** init выполняется и завершается ПЕРЕД app-контейнерами;
  sidecar работает РЯДОМ всё время жизни Pod.
- **Общий том.** init и app часто обмениваются данными через `emptyDir`,
  смонтированный в оба.

---

**Цель:** собрать Pod, где init-контейнер дожидается DNS и готовит файл, а
основной контейнер его читает.

**Ресурс:** `manifests/initcontainer/pod.yaml` — Pod `init-wait-dns`.

---

### 2.1 Pod с init-контейнером

Init-контейнер `wait-dns` (busybox) в цикле резолвит `kubernetes.default` и,
получив ответ, пишет `dns-ready` в `/work/status.txt` (том `emptyDir`).
Контейнер `app` читает этот файл в цикле.

```bash
kubectl -n lab apply -f manifests/initcontainer/pod.yaml

# Пока идёт init, STATUS = Init:0/1 (Ctrl+C когда дойдёт до Running)
kubectl -n lab get pod init-wait-dns -w
# NAME            READY   STATUS     RESTARTS   AGE
# init-wait-dns   0/1     Init:0/1   0          1s    <- init выполняется
# init-wait-dns   0/1     PodInitializing 0     3s    <- init завершён, стартует app
# init-wait-dns   1/1     Running    0          5s
```

```bash
# Логи именно init-контейнера (-c wait-dns)
kubectl -n lab logs init-wait-dns -c wait-dns
# Server:    10.96.0.10
# Name:      kubernetes.default.svc.cluster.local
# Address:   10.96.0.1            <- DNS ответил, цикл вышел, файл записан

# Логи основного контейнера (-c app) — видит файл от init
kubectl -n lab logs init-wait-dns -c app --tail=3
# dns-ready
```

> Без `-c <container>` команда `logs`/`exec` берёт первый app-контейнер, и логи
> init пришлось бы искать отдельно. У многоконтейнерного Pod всегда указывайте
> контейнер явно.

### 2.2 Порядок и обмен данными через emptyDir

```bash
# Статусы init-контейнеров отдельно от основных
kubectl -n lab get pod init-wait-dns \
  -o jsonpath='{.status.initContainerStatuses[0].state.terminated.reason}{"\n"}'
# Completed     <- init успешно завершился, иначе app не стартовал бы

# Файл реально лежит в общем emptyDir — проверим из app-контейнера
kubectl -n lab exec init-wait-dns -c app -- cat /work/status.txt
# dns-ready
```

**Контрольные вопросы:**
1. Что произойдёт с Pod, если init-контейнер завершится с ошибкой (exit 1)?
2. Чем init-контейнер отличается от sidecar по времени жизни?
3. Как init и основной контейнер обмениваются данными в этом примере?
4. Почему для `logs`/`exec` в этом Pod обязателен флаг `-c`?

---

## Часть 3: Пробы — readiness, liveness, startup

### Теория для изучения перед частью

- **readinessProbe** — «готов ли принимать трафик». Провал ⇒ Pod уходит из
  `Endpoints` сервиса, но НЕ перезапускается. Управляет маршрутизацией.
- **livenessProbe** — «жив ли процесс». Провал ⇒ kubelet **перезапускает**
  контейнер. Лечит зависания.
- **startupProbe** — «успел ли стартовать». Пока не пройдёт, liveness/readiness
  не выполняются. Защищает медленно стартующие приложения от преждевременного
  убийства liveness-пробой.
- **Типы проверок:** `httpGet` (2xx/3xx = успех), `tcpSocket` (порт открыт),
  `exec` (команда вернула 0), `grpc`.
- **Параметры:** `initialDelaySeconds`, `periodSeconds`, `timeoutSeconds`,
  `failureThreshold`, `successThreshold`.

| Проба | Вопрос | При провале |
|-------|--------|-------------|
| `readinessProbe` | готов принимать трафик? | убирается из `Endpoints`, **без** рестарта |
| `livenessProbe` | жив, не завис? | контейнер **перезапускается** |
| `startupProbe` | успел стартовать? | по threshold рестарт; до успеха блокирует liveness/readiness |

---

**Цель:** увидеть на живом приложении, как readiness рулит трафиком, а liveness —
рестартами.

**Ресурсы:** `manifests/probes/deploy.yaml` (`probe-demo`, nginx) + `svc.yaml`.

---

### 3.1 Рабочие пробы

```bash
kubectl -n lab apply -f manifests/probes/deploy.yaml -f manifests/probes/svc.yaml
kubectl -n lab rollout status deploy/probe-demo --timeout=120s
# deployment "probe-demo" successfully rolled out

# Обе пробы видны в describe
kubectl -n lab describe pod -l app=probe-demo | grep -E "Liveness|Readiness"
# Liveness:   http-get http://:80/ delay=10s timeout=1s period=10s #success=1 #failure=3
# Readiness:  http-get http://:80/ delay=3s  timeout=1s period=5s  #success=1 #failure=3
```

### 3.2 readiness ⇒ членство в Endpoints

```bash
# Pod Ready -> его IP в Endpoints сервиса
kubectl -n lab get endpoints probe-demo -o wide
# NAME         ENDPOINTS        AGE
# probe-demo   10.244.0.12:80   20s     <- есть backend, трафик пойдёт
```

### 3.3 liveness ⇒ рестарт контейнера

```bash
# Сломаем liveness изнутри: уберём страницу, которую проверяет проба по пути /.
# nginx начнёт отдавать 404 на / -> liveness фейлится 3 раза -> рестарт.
kubectl -n lab exec deploy/probe-demo -- sh -c 'mv /usr/share/nginx/html/index.html /tmp/'

# Через ~30-40с (delay10 + 3*period10) контейнер перезапустится
kubectl -n lab get pod -l app=probe-demo -w
# probe-demo-...   1/1   Running   0          ...
# probe-demo-...   1/1   Running   1 (2s ago) ...   <- RESTARTS вырос: liveness перезапустил

# Подтверждение причины — в events
kubectl -n lab describe pod -l app=probe-demo | grep -A1 "Liveness probe failed"
# Liveness probe failed: HTTP probe failed with statuscode: 404
# Container nginx failed liveness probe, will be restarted

# После рестарта образ nginx чист -> index.html снова на месте -> стабилизируется
```

> Разница на практике: провались тут **readiness** — Pod просто выпал бы из
> сервиса без рестарта. Провалилась **liveness** — контейнер перезапущен. Это и
> есть ключевое различие, которое надо уметь объяснять (критерий готовности).

### 3.4 startupProbe для медленного старта (фрагмент)

```yaml
# Если приложение стартует долго (прогрев кэша, миграции), startupProbe даёт ему
# время, отключая liveness/readiness до своего успеха:
startupProbe:
  httpGet: { path: /healthz, port: 80 }
  failureThreshold: 30      # до 30 * periodSeconds на старт
  periodSeconds: 10         # = до 300с прогрева, потом включаются liveness/readiness
```

**Контрольные вопросы:**
1. Чем по последствиям отличается провал `readinessProbe` от провала
   `livenessProbe`?
2. Зачем нужен `startupProbe`, если уже есть `initialDelaySeconds` у liveness?
3. Какие бывают типы проверок (`httpGet`/`tcpSocket`/`exec`/`grpc`) и когда
   уместен `exec`?
4. Что задаёт `failureThreshold` и как он влияет на скорость реакции?

---

## Часть 4: Ресурсы, QoS-классы и OOMKilled

### Теория для изучения перед частью

- **requests** — сколько гарантировать (scheduler ищет ноду с таким запасом).
  **limits** — потолок (cgroups режут CPU троттлингом, а превышение памяти →
  убийство контейнера OOM-killer'ом ядра).
- **QoS-класс** (вычисляется автоматически): **Guaranteed** (для всех ресурсов
  requests == limits), **Burstable** (есть requests, но не равны limits),
  **BestEffort** (нет ни requests, ни limits).
- **При memory pressure на ноде** kubelet вытесняет (evicts) поды в порядке:
  сначала `BestEffort`, потом `Burstable`, последними — `Guaranteed`.
- **OOMKilled** случается на уровне cgroup контейнера (превышен memory limit),
  даже если на ноде память есть. `exitCode 137` = 128 + SIGKILL(9).

---

**Цель:** определить QoS-класс пода и своими руками воспроизвести `OOMKilled`.

---

### 4.1 QoS-класс пода

```bash
# probe-demo: requests(64Mi/50m) != limits(128Mi/200m) => Burstable
kubectl -n lab get pod -l app=probe-demo -o jsonpath='{.items[0].status.qosClass}{"\n"}'
# Burstable

# Pod вообще без requests/limits был бы BestEffort; requests==limits => Guaranteed.
```

### 4.2 Воспроизведение OOMKilled

```bash
# Контейнер просит выделить 150 МБ при лимите 64 МБ -> cgroup OOM-killer убьёт его.
kubectl -n lab apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: oom-demo
  namespace: lab
spec:
  restartPolicy: Never
  containers:
  - name: hog
    image: polinux/stress
    command: ["stress"]
    args: ["--vm","1","--vm-bytes","150M","--vm-hang","0"]
    resources:
      limits:
        memory: "64Mi"
EOF

sleep 8
kubectl -n lab get pod oom-demo
# NAME       READY   STATUS      RESTARTS   AGE
# oom-demo   0/1     OOMKilled   0          8s
```

**Диагностика:**

```bash
# Причина и код выхода. Под с restartPolicy:Never не рестартует, поэтому причина
# лежит в state.terminated. (lastState заполняется только ПОСЛЕ рестарта — это
# случай Deployment/restartPolicy:Always, где OOM-причину искать именно там.)
kubectl -n lab get pod oom-demo \
  -o jsonpath='{.status.containerStatuses[0].state.terminated.reason}{" exit="}{.status.containerStatuses[0].state.terminated.exitCode}{"\n"}'
# OOMKilled exit=137       <- 137 = 128 + SIGKILL(9)

kubectl -n lab describe pod oom-demo | grep -A2 "State:"
# State:          Terminated
#   Reason:       OOMKilled
#   Exit Code:    137

kubectl -n lab delete pod oom-demo --ignore-not-found
```

> `exitCode 137` в проде почти всегда = OOM. Лечится либо поднятием
> `limits.memory`, либо починкой утечки/настройкой heap приложения.

**Контрольные вопросы:**
1. Как из `requests`/`limits` выводится QoS-класс? Приведите по примеру на
   каждый из трёх классов.
2. Почему OOMKilled может случиться, когда на ноде ещё есть свободная память?
3. Что означает `exitCode 137` и откуда берётся число 137?
4. В каком порядке kubelet вытесняет поды при нехватке памяти на ноде?

---

## Часть 5: Troubleshooting — боевые инциденты

### Теория для изучения перед частью

- Большинство lifecycle-инцидентов сводятся к рассогласованию между **пробой** и
  **реальным поведением приложения** (порт/путь/тайминг) либо между **лимитом** и
  **аппетитом** контейнера.
- Диагностический минимум: `get pod` (READY/STATUS/RESTARTS) → `describe pod`
  (блок Events, причины проб) → `logs`/`logs --previous` → `get endpoints`.

---

### Инцидент 1: Pod `Running`, но `0/1` — readiness бьётся в несуществующий путь

Оформлен как отдельный сценарий в `broken/scenario-01/` (там подсказки и
решение). Здесь — полный цикл.

**Воспроизведение:**

```bash
# readinessProbe.httpGet.path указывает на /does-not-exist (nginx отдаёт 404)
kubectl -n lab apply -f broken/scenario-01/deploy.yaml
sleep 12
```

**Диагностика:**

```bash
# 1) Running, но не Ready
kubectl -n lab get pods -l app=probe-demo
# probe-demo-...   0/1   Running   0   12s

# 2) Endpoints пуст -> Service без backend
kubectl -n lab get endpoints probe-demo
# probe-demo   <none>   ...

# 3) Причина — readiness получает 404
kubectl -n lab describe pod -l app=probe-demo | grep -A2 "Readiness probe failed"
# Readiness probe failed: HTTP probe failed with statuscode: 404
```

**Решение:**

```bash
# Вернуть корректный путь / (готовый манифест)
kubectl -n lab apply -f solutions/02-readiness-fail/deploy.yaml
kubectl -n lab rollout status deploy/probe-demo --timeout=120s
kubectl -n lab get endpoints probe-demo -o wide
# probe-demo   10.244.0.12:80   ...   <- backend вернулся
```

**Профилактика:** путь/порт пробы обязаны совпадать с тем, что реально отдаёт
приложение; для healthcheck заводят отдельный лёгкий эндпоинт (`/healthz`).

### Инцидент 2: `CrashLoopBackOff` из-за слишком строгой liveness

**Воспроизведение:**

```bash
# liveness стучится на порт, которого нет (8080), да ещё с малым initialDelay —
# контейнер не успевает «пожить» и бесконечно перезапускается.
kubectl -n lab apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: liveness-crash, namespace: lab }
spec:
  restartPolicy: Always
  containers:
  - name: nginx
    image: nginx:1.27-alpine
    livenessProbe:
      httpGet: { path: /, port: 8080 }   # nginx слушает 80, не 8080
      initialDelaySeconds: 1
      periodSeconds: 3
      failureThreshold: 1
EOF
sleep 20
```

**Диагностика и решение:**

```bash
kubectl -n lab get pod liveness-crash
# liveness-crash   0/1   CrashLoopBackOff   3 (10s ago)   20s

kubectl -n lab describe pod liveness-crash | grep -A1 "Liveness probe failed"
# Liveness probe failed: Get "http://10.244.0.x:8080/": connection refused
# Container nginx failed liveness probe, will be restarted

# Причина — порт пробы != порт приложения; чинится правкой port: 8080 -> 80.
kubectl -n lab delete pod liveness-crash --ignore-not-found
```

> Опасный антипаттерн: слишком агрессивная liveness (малый delay/threshold)
> устраивает рестарт-шторм у нормального приложения. liveness должна быть
> снисходительнее readiness.

### Бонус: быстрая диагностика lifecycle

```bash
# Поды с рестартами — кандидаты на CrashLoop/liveness-проблемы
kubectl -n lab get pods --sort-by=.status.containerStatuses[0].restartCount

# Свежие события namespace
kubectl -n lab get events --sort-by=.lastTimestamp | tail -15

# Причина последнего завершения у конкретного пода
kubectl -n lab get pod <pod> -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}{"\n"}'
```

**Контрольные вопросы:**
1. Pod `0/1 Running` с пустым `Endpoints`. Каким будет ваш порядок диагностики?
2. Почему чрезмерно строгая `livenessProbe` опаснее, чем её отсутствие?
3. Как отличить `CrashLoopBackOff` из-за liveness от падения самого приложения?

---

## Проверка модуля

Разверните рабочие манифесты (initcontainer + probes) и дождитесь готовности:

```bash
kubectl -n lab apply -f manifests/initcontainer/pod.yaml
kubectl -n lab apply -f manifests/probes/deploy.yaml -f manifests/probes/svc.yaml
kubectl -n lab rollout status deploy/probe-demo --timeout=120s

bash verify/verify.sh
# [OK] init-wait-dns pod applied, init-container status: Completed
# [OK] module 02 verified
```

В отличие от модуля 01, `verify.sh` здесь печатает **две** `[OK]`-строки: про
init-контейнер (`init-wait-dns`, статус `Completed`) и итоговую. Промежуточные
`require_*` при успехе молчат; если что-то не так, увидите `[WARN] ...` (мягкая
проверка init/проб) или `[FAIL] ...` с остановом. Например, если оставить
broken-вариант из Части 5 — упадёт на `[FAIL] service/probe-demo has no ready
endpoints in ns/lab`.

---

## Финальная карта ресурсов модуля

| Ресурс | Тип | Namespace | Что демонстрирует |
|--------|-----|-----------|-------------------|
| `init-wait-dns` | Pod (init + app) | `lab` | initContainer, порядок запуска, обмен через emptyDir |
| `probe-demo` | Deployment | `lab` | readiness/liveness, влияние на Endpoints и рестарты |
| `probe-demo` | Service (ClusterIP) | `lab` | выпадение Pod из Endpoints при NotReady |
| `oom-demo` | Pod (эфемерный) | `lab` | OOMKilled, exitCode 137, QoS |
| `liveness-crash` | Pod (эфемерный) | `lab` | CrashLoopBackOff из-за строгой liveness |

---

## Теоретические вопросы (итоговые)

### Блок 1: Фазы и состояния

1. Перечислите фазы Pod и состояния контейнера. Как они соотносятся?
2. Объясните на примере, почему Pod может быть `Running` при `READY 0/1`.
3. Как `restartPolicy` меняет поведение завершившегося контейнера?

### Блок 2: Init-контейнеры

4. Зачем init-контейнеры выделены отдельно? Приведите два реальных применения.
5. Что будет с Pod, если один из нескольких init-контейнеров упадёт?
6. Чем init-контейнер отличается от sidecar?

### Блок 3: Пробы

7. Сведите в таблицу различия `readiness`/`liveness`/`startup`: что проверяют,
   что происходит при провале.
8. Почему агрессивная `livenessProbe` — частая причина рукотворных аварий?
9. Когда `startupProbe` обязателен, а `initialDelaySeconds` недостаточно?

### Блок 4: Ресурсы, QoS, OOM

10. Как вычисляется QoS-класс? Дайте конфиг на `Guaranteed`, `Burstable`,
    `BestEffort`.
11. Почему `OOMKilled` происходит на уровне cgroup, а не всей ноды?
12. В каком порядке вытесняются поды при memory pressure и почему именно так?

---

## Шпаргалка

```bash
# === Фазы и состояния ===
kubectl -n lab get pod <p> -o jsonpath='{.status.phase}'
kubectl -n lab get pod <p> -o jsonpath='{.status.containerStatuses[0].state}'
kubectl -n lab get pod <p> -o jsonpath='{.status.qosClass}'        # QoS-класс
kubectl -n lab get pods -w                                          # фазы в реальном времени

# === Init / многоконтейнерные ===
kubectl -n lab logs <pod> -c <container>            # лог конкретного контейнера
kubectl -n lab logs <pod> --previous                # лог упавшего запуска
kubectl -n lab get pod <p> -o jsonpath='{.status.initContainerStatuses[0].state.terminated.reason}'

# === Пробы (диагностика) ===
kubectl -n lab describe pod -l app=probe-demo | grep -E "Liveness|Readiness"
kubectl -n lab describe pod <p> | grep -A2 "probe failed"
kubectl -n lab get endpoints <svc> -o wide          # пусто => readiness не проходит

# === Ресурсы / OOM ===
# Never/текущее завершение -> state.terminated; после рестарта (Always) -> lastState.terminated
kubectl -n lab get pod <p> -o jsonpath='{.status.containerStatuses[0].state.terminated.reason}'      # OOMKilled? (Never)
kubectl -n lab describe pod <p> | grep -A2 "State:"
kubectl top pod -n lab                               # факт. потребление (нужен metrics-server)

# === Развернуть/проверить модуль ===
kubectl -n lab apply -f manifests/initcontainer/pod.yaml
kubectl -n lab apply -f manifests/probes/deploy.yaml -f manifests/probes/svc.yaml
bash verify/verify.sh
```
