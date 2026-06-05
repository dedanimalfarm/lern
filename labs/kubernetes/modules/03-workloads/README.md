# Лабораторая работа 03: Workload-контроллеры (Deployment, Job/CronJob, DaemonSet, StatefulSet)

> ⏱ время ~25 мин · сложность 2/5 · пререквизиты: модуль 02

Цель: научиться выбирать правильный контроллер под задачу и управлять им —
выкатывать и откатывать `Deployment`, запускать разовые и периодические `Job`/
`CronJob`, раскатывать `DaemonSet` по нодам и понимать базовую идентичность
`StatefulSet`. К концу модуля вы аргументированно отвечаете «Deployment vs
StatefulSet vs Job» под конкретный сценарий.

---

## Предварительные требования

```bash
# kubeconfig нашего кластера (Kubespray); на другом стенде — свой путь/контекст
export KUBECONFIG=/root/.kube/kubespray.conf
# 1) Кластер, который реально запускает контейнеры (kind/minikube/k3s/GKE).
kubectl version --output=yaml | head -5

# 2) Namespace lab (идемпотентно). ВАЖНО: перед стартом убедитесь, что ns чист
#    от ресурсов прошлых модулей — иначе verify/endpoints поймают чужое.
kubectl create ns lab --dry-run=client -o yaml | kubectl apply -f -
kubectl -n lab get all

# 3) Для StatefulSet (Часть 4) нужен default StorageClass — volumeClaimTemplates
#    создаёт PVC. Проверим, что класс по умолчанию есть:
kubectl get storageclass
# NAME                 PROVISIONER             ... DEFAULT
# local-path (default) rancher.io/local-path   ... true     <- наш Kubespray; на GKE было бы standard-rwo
```

> Если default StorageClass нет — Часть 4 (StatefulSet с томами) не привяжет PVC
> (они зависнут в `Pending`). Остальные части от хранилища не зависят.

---

## Стартовая проверка

```bash
# Сколько нод — столько Pod создаст DaemonSet (Часть 3)
kubectl get nodes
# NAME       STATUS   ROLES           AGE   VERSION
# k8s-cp-1   Ready    control-plane   ...   v1.36.1
# k8s-w-1    Ready    <none>          ...   v1.36.1
# k8s-w-2    Ready    <none>          ...   v1.36.1   <- DaemonSet даст под на КАЖДУЮ schedulable-ноду

# Какие workload-типы вообще есть в API
kubectl api-resources | grep -E "deployments|statefulsets|daemonsets|jobs|cronjobs"
# deployments    apps/v1     true   Deployment
# statefulsets   apps/v1     true   StatefulSet
# daemonsets     apps/v1     true   DaemonSet
# jobs           batch/v1    true   Job
# cronjobs       batch/v1    true   CronJob
```

---

## Часть 1: Deployment — rollout и rollback

### Теория для изучения перед частью

- **Deployment** управляет stateless-репликами через `ReplicaSet`. Каждое
  изменение `template` создаёт НОВЫЙ ReplicaSet и плавно переносит на него поды.
- **Стратегии:** `RollingUpdate` (по умолчанию; постепенная замена с параметрами
  `maxSurge`/`maxUnavailable`) и `Recreate` (сначала убить все старые, потом
  поднять новые — допустим простой).
- **`maxSurge`** — сколько подов разрешено поднять СВЕРХ желаемого числа во время
  обновления; **`maxUnavailable`** — сколько разрешено увести НИЖЕ желаемого. Они
  задают компромисс «скорость выката ↔ запас доступности».
- **История и откат.** Deployment хранит прошлые ReplicaSet (`revisionHistoryLimit`),
  поэтому `rollout undo` откатывает без пересоздания ресурса. `change-cause`
  (аннотация `kubernetes.io/change-cause`) подписывает ревизию в истории.

**Иерархия владения (ownerReferences) и что делает rollout:**

```
Deployment/workload-demo  (ты редактируешь ЭТО)
   │ владеет (ownerReference), по одному RS на версию template
   ├── ReplicaSet -<hash-v1>   replicas=0   ◄── старая версия, держится для отката
   └── ReplicaSet -<hash-v2>   replicas=2
          │ владеет
          ├── Pod -<hash-v2>-xxxxx
          └── Pod -<hash-v2>-yyyyy

rollout v1->v2: НОВЫЙ RS поднимается (+maxSurge), старый ужимается (-maxUnavailable),
                пока новый не станет полным, старый — 0. undo: просто меняет местами.
```

```yaml
# стратегия в манифесте Deployment (значения по умолчанию — 25%/25%):
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate: { maxSurge: 25%, maxUnavailable: 25% }
```

**Readiness-проба управляет ПРОГРЕССОМ выката.** RollingUpdate двигается дальше,
только когда новый под становится `Ready`. Без readiness-пробы Deployment считает
под готовым сразу при `Running` — и выкатывает следующую порцию вслепую:

```
Шаг выката (maxUnavailable=0): поднять новый Pod ─► ждать пока Pod READY ──┐
                                                                          │
   READY?  ── нет ──► выкат ЖДЁТ (старые поды держат трафик)              │
     │ да                                                                 │
     └──► ужать старый Pod ──► повторить для следующего ◄─────────────────┘

Нет readiness-пробы ⇒ "Ready" = "Running" мгновенно ⇒ выкат катит дальше,
даже если новый под ещё не прогрелся и отдаёт 503 (битый релиз уедет целиком).
```

- **`minReadySeconds`** — под должен продержаться Ready хотя бы N секунд, прежде
  чем счёт пойдёт дальше (защита от «мигнул Ready и упал»).
- **`progressDeadlineSeconds`** (по умолч. 600с) — если выкат не двигается дольше
  дедлайна (новые поды не становятся Ready), Deployment ставит
  `Progressing=False, reason=ProgressDeadlineExceeded` — это сигнал «релиз застрял».
  Сам по себе rollout НЕ откатывается — откат руками (`rollout undo`).
- Связка: при `maxUnavailable=0` сломанная readiness **полностью останавливает**
  выкат, сохраняя старую рабочую версию в трафике — безопасное поведение по
  умолчанию. Подробно про сами пробы — модуль 02 (Часть 3).

---

**Цель:** выкатить v1, обновить до v2 и откатиться.

**Ресурсы:** `manifests/deployment/v1/` (`workload-demo` + svc), `v2/deploy.yaml`.

---

### 1.1 Deployment v1

```bash
kubectl -n lab apply -f manifests/deployment/v1/
kubectl -n lab rollout status deploy/workload-demo --timeout=120s
# deployment "workload-demo" successfully rolled out

# Deployment -> ReplicaSet -> 2 Pod
kubectl -n lab get deploy,rs,po -l app=workload-demo
# deployment.apps/workload-demo   2/2     2            2
# replicaset.apps/workload-demo-<h1>   2   2   2
# pod/workload-demo-<h1>-xxxxx     1/1   Running
# pod/workload-demo-<h1>-yyyyy     1/1   Running

# Версия видна в label и env
kubectl -n lab get pods -l app=workload-demo -L version
# ... version=v1
```

### 1.2 Rolling update на v2

```bash
# v2 меняет образ (1.27 -> 1.27.5-alpine) и подписан change-cause
kubectl -n lab apply -f manifests/deployment/v2/deploy.yaml

# Наблюдаем замену: появляется НОВЫЙ ReplicaSet, старый ужимается
kubectl -n lab get rs -l app=workload-demo
# NAME                       DESIRED   CURRENT   READY
# workload-demo-<h1>         0         0         0     <- старый (v1) свёрнут
# workload-demo-<h2>         2         2         2     <- новый (v2)

kubectl -n lab rollout status deploy/workload-demo
# deployment "workload-demo" successfully rolled out

kubectl -n lab get pods -l app=workload-demo -L version
# ... version=v2
```

> Старый ReplicaSet не удаляется — он остаётся с `DESIRED 0` именно для отката.

### 1.3 История и rollback

```bash
# История ревизий (CHANGE-CAUSE берётся из аннотации)
kubectl -n lab rollout history deploy/workload-demo
# REVISION  CHANGE-CAUSE
# 1         <none>
# 2         update to v2

# Откат на предыдущую ревизию
kubectl -n lab rollout undo deploy/workload-demo
kubectl -n lab rollout status deploy/workload-demo

# Убедиться, что вернулись на v1
kubectl -n lab get pods -l app=workload-demo -L version
# ... version=v1

# Откат на конкретную ревизию:
# kubectl -n lab rollout undo deploy/workload-demo --to-revision=2
```

### 1.4 Стратегии обновления

```bash
# Текущая стратегия и её параметры
kubectl -n lab get deploy workload-demo \
  -o jsonpath='{.spec.strategy.type}{" surge="}{.spec.strategy.rollingUpdate.maxSurge}{" unavail="}{.spec.strategy.rollingUpdate.maxUnavailable}{"\n"}'
# RollingUpdate surge=25% unavail=25%      <- значения по умолчанию
```

| Стратегия | Как обновляет | Простой | Когда |
|-----------|---------------|---------|-------|
| `RollingUpdate` | постепенно, по `maxSurge`/`maxUnavailable` | нет | по умолчанию для сервисов |
| `Recreate` | убить все старые → поднять новые | да | когда нельзя 2 версии разом (миграции БД, эксклюзивный том) |

**Контрольные вопросы:**
1. Что создаётся при каждом изменении `template` Deployment и зачем старый
   ReplicaSet остаётся с `DESIRED 0`?
2. Как `maxSurge` и `maxUnavailable` балансируют скорость выката и доступность?
3. Почему `rollout undo` возможен без ручного пересоздания Deployment?
4. Когда `Recreate` предпочтительнее `RollingUpdate`?

---

## Часть 2: Job и CronJob

### Теория для изучения перед частью

- **Job** выполняет задачу ДО успешного завершения. Ключевые поля:
  `completions` (сколько успешных запусков нужно), `parallelism` (сколько
  параллельно), `backoffLimit` (сколько повторов при падении),
  `restartPolicy` (`Never` — новый Pod на каждую попытку; `OnFailure` —
  перезапуск контейнера в том же Pod).
- **CronJob** создаёт Job по расписанию cron. Поля: `schedule`,
  `concurrencyPolicy` (`Allow`/`Forbid`/`Replace`), `startingDeadlineSeconds`,
  `successfulJobsHistoryLimit`/`failedJobsHistoryLimit`.
- Завершившиеся поды Job НЕ удаляются автоматически (если нет `ttlSecondsAfterFinished`) —
  это нужно, чтобы можно было прочитать их логи.

**Cron-выражение (5 полей `schedule`):**

```
┌─ минута (0-59)
│ ┌─ час (0-23)
│ │ ┌─ день месяца (1-31)
│ │ │ ┌─ месяц (1-12)
│ │ │ │ ┌─ день недели (0-6, 0=вс)
* * * * *
```

| schedule | Когда |
|----------|-------|
| `*/5 * * * *` | каждые 5 минут (наш `print-time-cron`) |
| `0 * * * *` | в начале каждого часа |
| `0 3 * * *` | каждый день в 03:00 |
| `0 0 * * 0` | каждое воскресенье в полночь |
| `*/15 9-17 * * 1-5` | каждые 15 мин, 9–17ч, пн–пт |

- **Indexed Completion** (`completionMode: Indexed`). Для параллельной обработки с
  «номерами»: каждый под получает `JOB_COMPLETION_INDEX` (0..completions-1) — удобно
  раздать шарды/части входа без внешней координации (vs дефолтный `NonIndexed`, где
  поды равнозначны).

---

**Цель:** запустить разовый Job и периодический CronJob, прочитать результат.

**Ресурсы:** `manifests/job/job.yaml` (`print-time`), `manifests/cronjob/cronjob.yaml`.

---

### 2.1 Job

```bash
kubectl -n lab apply -f manifests/job/job.yaml

# Дождаться завершения и посмотреть статус
kubectl -n lab wait --for=condition=complete job/print-time --timeout=60s
kubectl -n lab get job print-time
# NAME         STATUS     COMPLETIONS   DURATION   AGE
# print-time   Complete   1/1           5s         20s

# Логи пода Job — задача напечатала дату и job-done
kubectl -n lab logs job/print-time
# Mon Jun  2 ... 2026
# job-done
```

> `restartPolicy: Never` + `backoffLimit: 2` означают: при падении создаётся
> новый Pod, до 2 повторов, затем Job помечается `Failed`.

### 2.2 CronJob

```bash
kubectl -n lab apply -f manifests/cronjob/cronjob.yaml

kubectl -n lab get cronjob print-time-cron
# NAME              SCHEDULE      SUSPEND   ACTIVE   LAST SCHEDULE
# print-time-cron   */5 * * * *   False     0        <none>     <- ждёт ближайшую пятиминутку

# Не ждать 5 минут — триггернуть Job из CronJob вручную
kubectl -n lab create job --from=cronjob/print-time-cron cron-manual-1
kubectl -n lab wait --for=condition=complete job/cron-manual-1 --timeout=60s
kubectl -n lab logs job/cron-manual-1
# Mon Jun  2 ... 2026
```

> `concurrencyPolicy: Forbid` запрещает запуск нового Job, пока предыдущий не
> завершился, — защита от наложения долгих задач.

**Контрольные вопросы:**
1. Чем отличаются `restartPolicy: Never` и `OnFailure` для Job?
2. За что отвечают `completions` и `parallelism`?
3. Что делает `concurrencyPolicy: Forbid` у CronJob и зачем это нужно?
4. Как запустить Job из CronJob немедленно, не дожидаясь расписания?

---

## Часть 3: DaemonSet

### Теория для изучения перед частью

- **DaemonSet** гарантирует по одному Pod на каждой подходящей ноде (и
  автоматически — на новых нодах при их добавлении). Применение: агенты логов
  (fluentd), мониторинга (node-exporter), сетевые плагины (CNI), сторадж-демоны.
- Чтобы покрыть и control-plane ноды, DaemonSet нужны соответствующие
  `tolerations` (на мастер-нодах стоят taint'ы).
- `updateStrategy` (`RollingUpdate`/`OnDelete`) управляет тем, как
  обновляются поды DaemonSet.

**DaemonSet vs обычное планирование** (почему `replicas` нет):

| | Deployment-под | DaemonSet-под |
|---|---|---|
| Сколько | задаёшь `replicas` | по 1 на КАЖДУЮ подходящую ноду (считает контроллер) |
| Выбор ноды | **scheduler** (Filter+Score) | нода ФИКСИРОВАНА (`spec.nodeName` ставит DS) — scheduler не выбирает |
| Новая нода добавлена | ничего | DS сразу добавляет под на неё |
| Сужение нод | — | `spec.template.spec.nodeSelector`/`nodeAffinity` ограничивают, на какие ноды ставить |

> DaemonSet всё же уважает `taints`: чтобы под поехал на control-plane (taint
> `NoSchedule`), template нужен `tolerations` на этот taint. Системные DS (CNI,
> kube-proxy) их имеют — поэтому есть на всех нодах, включая мастер.

---

**Цель:** раскатать DaemonSet и убедиться, что Pod появился на каждой ноде.

**Ресурс:** `manifests/daemonset/ds.yaml` (`node-agent`).

---

### 3.1 DaemonSet по одному на ноду

```bash
kubectl -n lab apply -f manifests/daemonset/ds.yaml

kubectl -n lab get ds node-agent
# NAME         DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR
# node-agent   2         2         2       2            2           <none>
#              ^ DESIRED = числу нод (здесь 2)

# По одному Pod на каждой ноде — смотрим колонку NODE
kubectl -n lab get pods -l app=node-agent -o wide
# NAME               READY   STATUS    NODE
# node-agent-aaaaa   1/1     Running   gke-...-b02f
# node-agent-bbbbb   1/1     Running   gke-...-hj1s     <- разные ноды
```

> `DESIRED` у DaemonSet не задаётся руками — его выставляет контроллер по числу
> подходящих нод. Добавите ноду — DaemonSet сам добавит на неё Pod.

**Контрольные вопросы:**
1. Почему у DaemonSet нельзя задать `replicas`?
2. Что нужно, чтобы Pod DaemonSet поехали и на control-plane ноды?
3. Назовите три типичных применения DaemonSet.

---

## Часть 4: StatefulSet — базовая идентичность

### Теория для изучения перед частью

- **StatefulSet** даёт каждой реплике СТАБИЛЬНУЮ идентичность: имя с порядковым
  индексом (`web-0`, `web-1`), создание/удаление СТРОГО по порядку, и — через
  `volumeClaimTemplates` — собственный PVC на реплику (`data-web-0`, `data-web-1`),
  который переживает пересоздание Pod.
- **Headless Service** (`clusterIP: None`) даёт стабильные DNS-имена подов
  `web-0.web.<ns>.svc.cluster.local` — без него нет адресуемой идентичности.
- Отличие от Deployment: там поды взаимозаменяемы и имена случайны; здесь они
  именованы и «прилипают» к своему тому. (Глубоко тома/PV/PVC — в модуле 05.)

- **Порядок операций (по умолчанию `OrderedReady`):**

```
scale-up:     web-0 (ждём Ready) -> web-1 (ждём Ready) -> web-2 ...   (по возрастанию)
scale-down:   ... web-2 -> web-1 -> web-0                              (в ОБРАТНОМ порядке)
rolling update: тоже с конца (web-N первым) -> к web-0
```

  Зачем: для кворумных систем (БД, etcd) важно поднимать/гасить узлы предсказуемо,
  по одному. `podManagementPolicy: Parallel` отключает ожидание — все поды
  создаются/удаляются разом (когда строгий порядок не нужен, ради скорости).
- **При отказе ноды** StatefulSet НЕ пересоздаёт под автоматически (в отличие от
  Deployment): пока неясно, жив ли `web-0` где-то ещё, поднять второй `web-0` с тем
  же томом нельзя (риск split-brain/порчи данных). Под висит `Terminating`/`Unknown`,
  пока нода не вернётся или его не удалят принудительно.

---

**Цель:** поднять StatefulSet и увидеть упорядоченные имена, пер-реплика PVC и
DNS.

**Ресурсы:** `manifests/statefulset/svc-headless.yaml` (headless `web`) +
`sts.yaml` (StatefulSet `web`, 2 реплики).

---

### 4.1 Headless Service + StatefulSet

```bash
# Сначала headless Service, потом StatefulSet (он ссылается на serviceName)
kubectl -n lab apply -f manifests/statefulset/svc-headless.yaml
kubectl -n lab apply -f manifests/statefulset/sts.yaml
kubectl -n lab rollout status statefulset/web --timeout=180s

# Имена детерминированы и созданы ПО ПОРЯДКУ: сначала web-0, затем web-1
kubectl -n lab get pods -l app=web
# NAME    READY   STATUS    RESTARTS   AGE
# web-0   1/1     Running   0          40s
# web-1   1/1     Running   0          20s    <- появился ПОСЛЕ готовности web-0
```

### 4.2 PVC на каждую реплику

```bash
# volumeClaimTemplates создал отдельный PVC под каждый Pod
kubectl -n lab get pvc -l app=web
# NAME         STATUS   VOLUME      CAPACITY   ACCESS MODES   STORAGECLASS
# data-web-0   Bound    pvc-...     1Gi        RWO            standard-rwo
# data-web-1   Bound    pvc-...     1Gi        RWO            standard-rwo

# Стабильное DNS-имя реплики через headless Service
kubectl -n lab run dns --image=busybox:1.36 --restart=Never -i --rm -- \
  nslookup web-0.web.lab.svc.cluster.local
# Name:      web-0.web.lab.svc.cluster.local
# Address:   10.20.x.x         <- конкретный Pod web-0
```

> Удалите `web-0` — StatefulSet пересоздаст Pod с ТЕМ ЖЕ именем и подключит ТОТ
> ЖЕ `data-web-0`. В Deployment имя было бы новым, а том — не «прилип» бы.

**Контрольные вопросы:**
1. Чем имена подов StatefulSet отличаются от Deployment и почему это важно для
   stateful-приложений?
2. Зачем StatefulSet нужен headless Service?
3. Что создаёт `volumeClaimTemplates` и что станет с PVC при пересоздании Pod?
4. В каком порядке StatefulSet создаёт и удаляет поды?

---

## Часть 5: Troubleshooting — боевые инциденты

### Теория для изучения перед частью

- Выкат «не доезжает» обычно по двум причинам: новый Pod не может СТАРТОВАТЬ
  (образ/конфиг) либо не становится READY (пробы). При `RollingUpdate` это не
  роняет сервис сразу — старые поды держат трафик, пока новые не готовы.
- Диагностика выката: `rollout status` (с таймаутом) → `get pods` (что с новыми)
  → `describe`/`events` → при необходимости `rollout undo`.

---

### Инцидент 1: rollout завис — ImagePullBackOff

Оформлен как сценарий в `broken/scenario-01/`. Здесь — полный цикл.

**Воспроизведение:**

```bash
# Образ с несуществующим тегом
kubectl -n lab apply -f broken/scenario-01/deploy.yaml
sleep 8
```

**Диагностика:**

```bash
kubectl -n lab get pods -l app=workload-demo
# workload-demo-...   0/1   ImagePullBackOff   0   8s

# Причина — в events пода
kubectl -n lab describe pod -l app=workload-demo | grep -A2 -E "Failed|Back-off"
# Failed to pull image "nginx:not-a-real-tag": ... not found
# Back-off pulling image "nginx:not-a-real-tag"

# rollout честно сообщает, что не дождался
kubectl -n lab rollout status deploy/workload-demo --timeout=15s
# error: deployment "workload-demo" exceeded its progress deadline
```

**Решение:**

```bash
kubectl -n lab apply -f solutions/01-imagepull/deploy.yaml
kubectl -n lab rollout status deploy/workload-demo --timeout=120s
# либо быстрый откат на рабочую ревизию:
# kubectl -n lab rollout undo deploy/workload-demo
```

**Профилактика:** пинить существующие теги/дайджесты, проверять доступность
образа в CI; `RollingUpdate` сам не даст битой версии вытеснить рабочую, если
старые поды Ready.

### Инцидент 2: Job падает в backoff

**Воспроизведение и диагностика:**

```bash
# Job с заведомо падающей командой (exit 1), backoffLimit 2
kubectl -n lab apply -f - <<'EOF'
apiVersion: batch/v1
kind: Job
metadata: { name: failing-job, namespace: lab }
spec:
  backoffLimit: 2
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: f
        image: busybox:1.36
        command: ["sh","-c","echo trying; exit 1"]
EOF
sleep 20

kubectl -n lab get job failing-job
# NAME          STATUS   COMPLETIONS   DURATION   AGE
# failing-job   Failed   0/1           ...        20s

# Каждая попытка — отдельный Pod (restartPolicy: Never); их видно:
kubectl -n lab get pods -l job-name=failing-job
# failing-job-aaaaa   0/1   Error
# failing-job-bbbbb   0/1   Error
# failing-job-ccccc   0/1   Error     <- backoffLimit=2 => всего 1+2=3 попытки
kubectl -n lab logs -l job-name=failing-job --tail=1
# trying
kubectl -n lab delete job failing-job
```

**Профилактика:** `backoffLimit` + алёрт на `Failed`-джобы; идемпотентность
задачи, чтобы повтор был безопасен.

### Бонус: PodDisruptionBudget и drain

```bash
# PDB ограничивает ДОБРОВОЛЬНЫЕ выселения (drain ноды при обслуживании),
# не давая увести слишком много реплик разом:
kubectl -n lab apply -f - <<'EOF'
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: { name: workload-pdb, namespace: lab }
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: workload-demo
EOF
kubectl -n lab get pdb workload-pdb
# NAME           MIN AVAILABLE   ALLOWED DISRUPTIONS
# workload-pdb   1               1
# При `kubectl drain <node>` Kubernetes уважает PDB и не уведёт последнюю реплику.
kubectl -n lab delete pdb workload-pdb
```

**Контрольные вопросы:**
1. Почему битый выкат при `RollingUpdate` не роняет сервис сразу?
2. Чем `rollout undo` удобнее ручного пересоздания при сбойном релизе?
3. Как `PodDisruptionBudget` влияет на `kubectl drain`?

---

## Проверка модуля

Разверните рабочие манифесты (Deployment + Service + Job + CronJob + DaemonSet) и
дайте Job завершиться:

```bash
kubectl -n lab apply -f manifests/deployment/v1/
kubectl -n lab apply -f manifests/job/job.yaml
kubectl -n lab apply -f manifests/cronjob/cronjob.yaml
kubectl -n lab apply -f manifests/daemonset/ds.yaml
kubectl -n lab wait --for=condition=complete job/print-time --timeout=60s

bash verify/verify.sh
# [OK] job/print-time completed
# [OK] cronjob/print-time-cron exists
# [OK] module 03 verified
```

`verify.sh` проверяет цепочку модуля: namespace `lab` → `Deployment/workload-demo`
готов → `Service/workload-demo` с непустыми `Endpoints` → `DaemonSet/node-agent`
(`ready == desired`) → `Job/print-time` завершён → `CronJob/print-time-cron`
существует. Промежуточные `require_*` при успехе молчат; три `[OK]`-строки
печатают `ok`-вызовы (Job, CronJob, итог). Job обязательно должен УСПЕТЬ
завершиться до запуска — иначе `[WARN] job/print-time has not completed yet`.

---

## Финальная карта ресурсов модуля

| Ресурс | Тип | Что демонстрирует |
|--------|-----|-------------------|
| `workload-demo` | Deployment + Service | rollout/rollback, RollingUpdate, история ревизий |
| `print-time` | Job | разовая задача до завершения, backoffLimit |
| `print-time-cron` | CronJob | запуск по расписанию, concurrencyPolicy |
| `node-agent` | DaemonSet | по одному Pod на ноду |
| `web` + `web` (headless) | StatefulSet + Service | стабильные имена `web-0/1`, PVC `data-web-*`, DNS |

### Когда какой контроллер

| Нужно | Контроллер |
|-------|-----------|
| Stateless-сервис с масштабированием и выкатами | **Deployment** |
| Стабильные имена + свой том на реплику (БД, кворумы) | **StatefulSet** |
| По агенту на каждой ноде (логи/мониторинг/CNI) | **DaemonSet** |
| Разовая задача до завершения (миграция, бэкап) | **Job** |
| Периодическая задача по расписанию | **CronJob** |

---

## Теоретические вопросы (итоговые)

### Блок 1: Deployment

1. Опишите путь обновления Deployment через ReplicaSet. Почему старые RS не
   удаляются?
2. Как `maxSurge`/`maxUnavailable` влияют на доступность во время выката?
3. Что такое `change-cause` и как он помогает при разборе инцидента релиза?

### Блок 2: Job / CronJob

4. Сравните `restartPolicy: Never` и `OnFailure` для Job по числу создаваемых Pod.
5. Что произойдёт при `concurrencyPolicy: Forbid`, если предыдущий Job ещё идёт?
6. Зачем у завершённых Job остаются Pod и как их автоматически убирать?

### Блок 3: DaemonSet

7. Почему `DESIRED` у DaemonSet нельзя задать вручную?
8. Что нужно, чтобы DaemonSet покрыл control-plane ноды?

### Блок 4: StatefulSet

9. Какие три гарантии даёт StatefulSet по сравнению с Deployment?
10. Зачем StatefulSet headless Service и что он даёт по DNS?
11. Что случится с `data-web-0` при удалении и пересоздании Pod `web-0`?
12. В каком порядке StatefulSet поднимает и ГАСИТ поды (OrderedReady)? Что меняет
    `podManagementPolicy: Parallel`?
13. Почему StatefulSet НЕ пересоздаёт под при отказе ноды автоматически?

---

## Практические задания (отработка)

> Делайте на живом кластере; проверяйте себя командами и `verify/verify.sh`.

1. Сделайте RollingUpdate с `maxSurge=1/maxUnavailable=0`, понаблюдайте смену ReplicaSet, затем `rollout undo`.
2. CronJob: триггерните Job вручную (`create job --from=cronjob/...`), смените `schedule`, проверьте `concurrencyPolicy`.
3. Удалите `web-0` StatefulSet — убедитесь, что вернулось ТО ЖЕ имя и подключился ТОТ ЖЕ PVC `data-web-0`.
4. Добавьте DaemonSet `nodeSelector` на метку и посмотрите, как меняется `DESIRED`.
5. Запустите Job с `completions: 4, parallelism: 2, completionMode: Indexed`, найдите `JOB_COMPLETION_INDEX` в подах.

---

## Шпаргалка

```bash
# === Deployment ===
kubectl -n lab apply -f manifests/deployment/v1/
kubectl -n lab set image deploy/workload-demo app=nginx:1.27.5-alpine
kubectl -n lab rollout status deploy/workload-demo
kubectl -n lab rollout history deploy/workload-demo
kubectl -n lab rollout undo deploy/workload-demo [--to-revision=N]
kubectl -n lab get rs -l app=workload-demo            # старый(0)+новый(N)

# === Job / CronJob ===
kubectl -n lab apply -f manifests/job/job.yaml
kubectl -n lab wait --for=condition=complete job/print-time --timeout=60s
kubectl -n lab logs job/print-time
kubectl -n lab create job --from=cronjob/print-time-cron run-now   # триггер вручную

# === DaemonSet ===
kubectl -n lab get ds node-agent
kubectl -n lab get pods -l app=node-agent -o wide     # по Pod на ноду

# === StatefulSet ===
kubectl -n lab apply -f manifests/statefulset/svc-headless.yaml -f manifests/statefulset/sts.yaml
kubectl -n lab get pods -l app=web                    # web-0, web-1 по порядку
kubectl -n lab get pvc -l app=web                     # data-web-0, data-web-1

# === Проверка / Уборка ===
bash verify/verify.sh
kubectl -n lab delete -k manifests/                   # снести всё из kustomization
kubectl -n lab delete pvc -l app=web                  # PVC от StatefulSet удаляются ОТДЕЛЬНО
```

---

## Уборка

StatefulSet НЕ удаляет свои PVC автоматически — их надо снести отдельно, иначе
останутся висеть (и тратить диск):

```bash
kubectl -n lab delete -k manifests/          # Deployment/Svc/Job/CronJob/DS/STS/headless
kubectl -n lab delete pvc -l app=web         # тома StatefulSet
# либо целиком ресурсы модуля в lab:
kubectl -n lab delete deploy,sts,ds,job,cronjob,svc,pvc --all
```
