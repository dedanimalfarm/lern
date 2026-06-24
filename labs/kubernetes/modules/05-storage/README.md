# Лабораторная работа 05: Хранилище в Kubernetes (volumes, PV/PVC, StatefulSet)

## Оглавление
<!-- TOC -->
- [Предварительные требования](#предварительные-требования)
- [Стартовая проверка](#стартовая-проверка)
- [Часть 1: Эфемерные тома (emptyDir) и привязка к ноде (hostPath)](#часть-1-эфемерные-тома-emptydir-и-привязка-к-ноде-hostpath)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью)
  - [1.1 emptyDir как общий том между контейнерами](#11-emptydir-как-общий-том-между-контейнерами)
  - [1.2 Жизненный цикл emptyDir: рестарт контейнера vs пересоздание Pod](#12-жизненный-цикл-emptydir-рестарт-контейнера-vs-пересоздание-pod)
  - [1.3 hostPath: монтирование каталога ноды](#13-hostpath-монтирование-каталога-ноды)
  - [1.4 Почему hostPath опасен в production](#14-почему-hostpath-опасен-в-production)
- [Часть 2: PersistentVolume, PersistentVolumeClaim и StorageClass](#часть-2-persistentvolume-persistentvolumeclaim-и-storageclass)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-1)
  - [2.1 Динамическое provisioning: PVC создаёт PV сам](#21-динамическое-provisioning-pvc-создаёт-pv-сам)
  - [2.2 PVC + Pod: привязка и accessModes](#22-pvc--pod-привязка-и-accessmodes)
  - [2.3 volumeBindingMode: Immediate vs WaitForFirstConsumer](#23-volumebindingmode-immediate-vs-waitforfirstconsumer)
  - [2.4 reclaimPolicy: что станет с PV после удаления PVC](#24-reclaimpolicy-что-станет-с-pv-после-удаления-pvc)
  - [2.5 Статическое provisioning: PV руками](#25-статическое-provisioning-pv-руками)
  - [2.6 Расширение тома (online resize)](#26-расширение-тома-online-resize)
- [Часть 3: StatefulSet + volumeClaimTemplates + headless Service](#часть-3-statefulset--volumeclaimtemplates--headless-service)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-2)
  - [3.1 Headless Service и стабильные DNS-имена](#31-headless-service-и-стабильные-dns-имена)
  - [3.2 StatefulSet с volumeClaimTemplates](#32-statefulset-с-volumeclaimtemplates)
  - [3.3 Сохранность данных при пересоздании Pod](#33-сохранность-данных-при-пересоздании-pod)
  - [3.4 Масштабирование и судьба PVC](#34-масштабирование-и-судьба-pvc)
- [Часть 4: Troubleshooting — боевые инциденты](#часть-4-troubleshooting--боевые-инциденты)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-3)
  - [Инцидент 1: PVC висит в Pending — несуществующий StorageClass](#инцидент-1-pvc-висит-в-pending--несуществующий-storageclass)
  - [Инцидент 2: PVC Pending, хотя StorageClass есть (WaitForFirstConsumer)](#инцидент-2-pvc-pending-хотя-storageclass-есть-waitforfirstconsumer)
  - [Инцидент 3: Pod не стартует — Multi-Attach error (RWO на двух нодах)](#инцидент-3-pod-не-стартует--multi-attach-error-rwo-на-двух-нодах)
  - [Бонус: общая диагностика storage](#бонус-общая-диагностика-storage)
- [Проверка модуля](#проверка-модуля)
- [Финальная карта ресурсов модуля](#финальная-карта-ресурсов-модуля)
- [Теоретические вопросы (итоговые)](#теоретические-вопросы-итоговые)
  - [Блок 1: Тома и жизненный цикл данных](#блок-1-тома-и-жизненный-цикл-данных)
  - [Блок 2: PV/PVC/StorageClass](#блок-2-pvpvcstorageclass)
  - [Блок 3: accessModes и многонодовость](#блок-3-accessmodes-и-многонодовость)
  - [Блок 4: StatefulSet](#блок-4-statefulset)
  - [Блок 5: Troubleshooting](#блок-5-troubleshooting)
- [Чему вы научились](#чему-вы-научились)
- [Уборка](#уборка)
- [Практические задания (отработка)](#практические-задания-отработка)
- [Шпаргалка](#шпаргалка)
<!-- /TOC -->


> ⏱ время ~25 мин · сложность 2/5 · пререквизиты: модуль 03

---

Цель всей работы: научиться осознанно выбирать тип тома под задачу, понимать
полный путь данных `StorageClass → PV → PVC → Pod`, видеть разницу между
эфемерным и постоянным хранилищем и уметь диагностировать типовые сбои
storage-подсистемы.

> Все манифесты этой работы лежат в `manifests/`, поломки — в `broken/`,
> эталонные решения — в `solutions/`, автопроверка — в `verify/verify.sh`.
> README — это полный сценарий прохождения; манифесты применяются как файлы.

---

## Предварительные требования

```bash
# kubeconfig нашего кластера (Kubespray); на другом стенде — свой путь/контекст
export KUBECONFIG=/root/.kube/kubespray.conf
# 1) Рабочий кластер и kubectl, который в него смотрит
kubectl version
kubectl cluster-info

# 2) Нужен хотя бы один StorageClass с провижинером (для динамического PVC).
kubectl get storageclass
```

Если StorageClass'ов нет (вывод `No resources found`) — поставьте локальный
провижинер. Самый простой для одно-нодового стенда (kind/minikube/bare):

```bash
# local-path-provisioner от Rancher: динамический hostPath-based StorageClass.
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.31/deploy/local-path-storage.yaml

# Сделать его дефолтным, чтобы PVC без storageClassName использовали его
kubectl patch storageclass local-path \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

kubectl get storageclass
```

```
NAME                   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION
local-path (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false
```

> **Запомните три колонки справа — они определяют половину поведения в этой работе:**
> - `RECLAIMPOLICY` (`Delete`/`Retain`) — что станет с PV после удаления PVC.
> - `VOLUMEBINDINGMODE` (`Immediate`/`WaitForFirstConsumer`) — когда PVC перейдёт в `Bound`.
> - `ALLOWVOLUMEEXPANSION` (`true`/`false`) — можно ли расширить том на лету.
>
> У k3s (`local-path`), kind и minikube по умолчанию режим
> **`WaitForFirstConsumer`** — это значит, что одинокий PVC **не привяжется**,
> пока его не смонтирует Pod. Это не баг, а топологически-осознанное связывание
> (см. Часть 2.3 и Инцидент 2).

```bash
# 3) Namespace для всех ресурсов лабы
kubectl create ns lab --dry-run=client -o yaml | kubectl apply -f -

# Удобный алиас на время работы
alias k='kubectl -n lab'
```

---

## Стартовая проверка

```bash
# Какие классы хранения доступны и какой из них default
kubectl get sc

# Уже есть PV/PVC в кластере? (чистый стенд — пусто)
kubectl get pv
kubectl -n lab get pvc

# На скольких нодах работаем (важно для accessModes и Multi-Attach)
kubectl get nodes -o wide
```

> **Важно:** число нод влияет на сценарии. `ReadWriteOnce`-том можно
> примонтировать только на **одной ноде одновременно** — на многонодовом
> кластере это источник ошибки `Multi-Attach` (Инцидент 3). На одно-нодовом
> стенде эта ошибка не воспроизводится — учитывайте, где вы запускаете лабу.

---

## Часть 1: Эфемерные тома (emptyDir) и привязка к ноде (hostPath)

### Теория для изучения перед частью

- Что такое `Volume` в Pod и чем он отличается от тома Docker
- Уровни жизненного цикла данных: контейнер → Pod → нода → кластер
- `emptyDir`: где физически лежит (диск ноды vs `medium: Memory` = tmpfs)
- Почему `emptyDir` переживает рестарт контейнера, но не пересоздание Pod
- `hostPath`: монтирование пути ноды внутрь контейнера, поле `type`
- Почему `hostPath` опасен: выход за пределы контейнера, доступ к хосту, непереносимость
- Эфемерное хранилище и его учёт в `requests/limits` (`ephemeral-storage`)

---

**Цель:** на практике увидеть границы жизни данных и понять, почему эфемерные
тома не годятся для состояния, которое нельзя терять.

**Ресурсы:** `manifests/emptydir/pod.yaml`, `manifests/hostpath/pod.yaml`

---

### 1.1 emptyDir как общий том между контейнерами

`emptyDir` создаётся пустым при старте Pod и существует, пока Pod жив. Его удобно
использовать как канал обмена данными между контейнерами одного Pod.

Манифест `manifests/emptydir/pod.yaml` — два контейнера, общий том `cache`:

```yaml
spec:
  volumes:
  - name: cache
    emptyDir: {}          # пустой том на диске ноды; {} = медиум по умолчанию
  containers:
  - name: writer          # пишет дату в файл каждые 5 секунд
    image: busybox:1.36   # триггер /tmp/crash роняет контейнер (для демо рестарта в 1.2)
    command: ["sh", "-c", "while true; do [ -f /tmp/crash ] && exit 1; date >> /cache/out.log; sleep 5; done"]
    volumeMounts:
    - { name: cache, mountPath: /cache }
  - name: reader          # читает тот же файл из общего тома
    image: busybox:1.36
    command: ["sh", "-c", "tail -f /cache/out.log"]
    volumeMounts:
    - { name: cache, mountPath: /cache }
```

```bash
# Применить Pod с двумя контейнерами
kubectl -n lab apply -f manifests/emptydir/pod.yaml

# Дождаться Running (оба контейнера 2/2)
kubectl -n lab get pod storage-emptydir -w
# storage-emptydir   2/2   Running   0   12s   <- Ctrl+C когда дойдёт до 2/2

# reader видит то, что пишет writer — данные общие
kubectl -n lab logs storage-emptydir -c reader --tail=5
```

```
Sat May 30 12:00:05 UTC 2026
Sat May 30 12:00:10 UTC 2026
Sat May 30 12:00:15 UTC 2026   <- reader читает файл, который наполняет writer
```

```bash
# Где физически лежит том? На диске ноды под каталогом kubelet:
# /var/lib/kubelet/pods/<pod-uid>/volumes/kubernetes.io~empty-dir/cache
# Узнать UID пода:
kubectl -n lab get pod storage-emptydir -o jsonpath='{.metadata.uid}{"\n"}'
```

> **RAM-вариант:** `emptyDir: { medium: Memory, sizeLimit: 128Mi }` разместит том
> в tmpfs (как RAM-диск). Данные ещё быстрее, но занимают память контейнера и
> учитываются в его memory-лимите.

### 1.2 Жизненный цикл emptyDir: рестарт контейнера vs пересоздание Pod

Ключевое различие, которое путают чаще всего.

```bash
# Положим маркер в том
kubectl -n lab exec storage-emptydir -c writer -- sh -c 'echo MARKER > /cache/marker.txt'
kubectl -n lab exec storage-emptydir -c writer -- cat /cache/marker.txt
# MARKER

# (а) Перезапуск КОНТЕЙНЕРА — данные ВЫЖИВАЮТ.
# ВАЖНО: `kill 1` не сработает — PID 1 в namespace контейнера защищён ядром от
# сигналов без обработчика даже изнутри. Роняем контейнер триггером в ЕГО
# собственной (эфемерной) ФС /tmp — не в /cache, иначе после рестарта будет
# crashloop. Цикл увидит /tmp/crash, выйдет с кодом 1, kubelet перезапустит контейнер:
kubectl -n lab exec storage-emptydir -c writer -- touch /tmp/crash
sleep 8
kubectl -n lab get pod storage-emptydir   # RESTARTS у writer вырос на 1
# на рестарте /tmp обнуляется (триггер исчез) — контейнер снова стабилен
kubectl -n lab exec storage-emptydir -c writer -- cat /cache/marker.txt
# MARKER   <- том пережил рестарт контейнера
```

```bash
# (б) Пересоздание POD — данные ТЕРЯЮТСЯ.
kubectl -n lab delete pod storage-emptydir
kubectl -n lab apply -f manifests/emptydir/pod.yaml
kubectl -n lab wait --for=condition=Ready pod/storage-emptydir --timeout=60s
kubectl -n lab exec storage-emptydir -c writer -- cat /cache/marker.txt
# cat: can't open '/cache/marker.txt': No such file or directory   <- данные исчезли
```

> **Вывод:** `emptyDir` привязан к жизни Pod, а не контейнера. Любой
> `kubectl delete pod`, вытеснение (eviction), перенос на другую ноду или падение
> ноды уничтожают данные. Для состояния, которое нельзя терять, нужен PVC (Часть 2).

### 1.3 hostPath: монтирование каталога ноды

`hostPath` пробрасывает в Pod каталог с файловой системы **ноды**.

```yaml
# manifests/hostpath/pod.yaml
spec:
  volumes:
  - name: host-data
    hostPath:
      path: /tmp/k8s-lab-hostpath
      type: DirectoryOrCreate     # создать каталог, если его нет
```

| `type` | Поведение |
|--------|-----------|
| `""` (пусто) | Никаких проверок |
| `DirectoryOrCreate` | Создать каталог (0755), если отсутствует |
| `Directory` | Каталог обязан существовать, иначе Pod не стартует |
| `FileOrCreate` / `File` | То же для файла |
| `Socket` | Должен быть UNIX-сокет (напр. `/var/run/docker.sock`) |

```bash
kubectl -n lab apply -f manifests/hostpath/pod.yaml
kubectl -n lab wait --for=condition=Ready pod/storage-hostpath --timeout=60s

# Контейнер пишет в /host -> это /tmp/k8s-lab-hostpath на НОДЕ
kubectl -n lab exec storage-hostpath -- sh -c 'cat /host/data.log | tail -3'

# На каком узле оказался Pod — данные физически там, и только там
kubectl -n lab get pod storage-hostpath -o jsonpath='{.spec.nodeName}{"\n"}'
```

> **Грабли переносимости:** если Pod пересоздастся на другой ноде, `/tmp/k8s-lab-hostpath`
> там будет пустым — данные «остались» на прежнем узле. hostPath неявно
> «привязывает» состояние к конкретной ноде.

### 1.4 Почему hostPath опасен в production

- **Побег из контейнера:** примонтировав `hostPath: /` или `/var/run/...`,
  процесс получает доступ к файлам хоста и фактически к самой ноде.
- **Непереносимость:** scheduler может увести Pod на ноду, где нужного пути нет.
- **Нет изоляции и квот:** Pod может забить диск ноды и положить kubelet.

```bash
# Аудит: кто в кластере использует hostPath (одна из проверок безопасности)
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\t"}{.spec.volumes[?(@.hostPath)].hostPath.path}{"\n"}{end}' | grep -v '	$'
```

**Таблица: когда какой том применять**

| Том | Жизнь данных | Между нодами | Типичное применение |
|-----|--------------|--------------|---------------------|
| `emptyDir` | Жизнь Pod | Нет | Кэш, scratch, обмен между контейнерами Pod |
| `emptyDir{medium:Memory}` | Жизнь Pod | Нет | Сверхбыстрый временный буфер (tmpfs) |
| `hostPath` | Жизнь данных на ноде | Нет (привязка к ноде) | Системные агенты (DaemonSet), доступ к `/var/log` |
| `PVC` (PV) | Независимо от Pod | Зависит от провижинера | Любое состояние, которое нельзя терять |

**Контрольные вопросы:**
1. Почему данные в `emptyDir` переживают рестарт контейнера, но не `kubectl delete pod`?
2. Чем `emptyDir: {}` отличается от `emptyDir: {medium: Memory}` по месту хранения и учёту ресурсов?
3. Какой `type` у hostPath заставит Pod не стартовать, если каталога нет?
4. Назовите два способа, которыми `hostPath` ломает безопасность ноды.
5. Pod с hostPath переехал на другую ноду и «потерял» данные. Почему это ожидаемо?

---

## Часть 2: PersistentVolume, PersistentVolumeClaim и StorageClass

### Теория для изучения перед частью

- Разделение ролей: `PV` (ресурс, кластерный) vs `PVC` (запрос, в namespace)
- Динамическое provisioning (StorageClass + провижинер) vs статическое (ручной PV)
- `accessModes`: `RWO`, `ROX`, `RWX`, `RWOP` — и что это значит на уровне нод
- `volumeBindingMode`: `Immediate` vs `WaitForFirstConsumer` (топология)
- `reclaimPolicy`: `Retain` vs `Delete` — судьба PV после удаления PVC
- Дефолтный StorageClass и смысл `storageClassName: ""`
- `allowVolumeExpansion` и онлайн-расширение тома
- Фазы PV/PVC: `Available → Bound → Released → Failed`

#### Как PVC находит свой PV (критерии матчинга)

Когда PVC ищет, к какому PV привязаться (или какой PV создать динамически),
контроллер binding проверяет **все** условия одновременно:

| Критерий | Правило связывания |
|---|---|
| `storageClassName` | должен **совпадать** строка-в-строку (пустой `""` PVC ↔ PV без класса; не указан у PVC ⇒ берётся default-класс) |
| `accessModes` | PV обязан поддерживать **все** режимы, запрошенные PVC (PV — надмножество) |
| `capacity` | `PV.capacity >= PVC.requests.storage` (можно получить том БОЛЬШЕ запроса) |
| `volumeName` | если PVC явно указал `volumeName: X` — привяжется только к этому PV |
| `selector` | `matchLabels`/`matchExpressions` PVC должны совпасть с метками PV |
| `volumeMode` | `Filesystem` (по умолчанию) vs `Block` — должны совпасть |

- **Связывание эксклюзивно и 1:1**: один PV ↔ один PVC. Привязанный PV не
  отдадут другому claim, даже если в нём много места.
- **Динамика vs статика**: если подходящего `Available` PV нет, но у класса есть
  провижинер — PV создаётся под запрос (capacity = ровно `requests`). Если
  провижинера нет — PVC висит `Pending` (см. Часть 4, Инцидент 1).
- `WaitForFirstConsumer` откладывает и матчинг, и создание PV до появления Pod —
  чтобы выбрать топологию (зону/ноду) под реального потребителя.

#### CSI-архитектура (и почему в нашей лабе её НЕТ)

Современный k8s общается с системами хранения через **CSI** (Container Storage
Interface) — out-of-tree плагины. У CSI-драйвера две части:

```
        ┌─────────────────── Controller Plugin (Deployment, 1 на кластер) ──────────────────┐
        │  CSI-драйвер  +  внешние sidecar-контроллеры (поставляет сообщество k8s):          │
        │   • external-provisioner  — видит новый PVC → зовёт CreateVolume   (создать том)   │
        │   • external-attacher     → ControllerPublishVolume   (присоединить том к ноде)    │
        │   • external-resizer      → ControllerExpandVolume    (онлайн-расширение)          │
        │   • external-snapshotter  → CreateSnapshot            (снапшоты)                    │
        └───────────────────────────────────────────────────────────────────────────────────┘
        ┌─────────────────── Node Plugin (DaemonSet, на каждой ноде) ───────────────────────┐
        │   CSI-драйвер  +  node-driver-registrar  → NodeStageVolume / NodePublishVolume     │
        │   (форматирует и монтирует том в каталог Pod на конкретной ноде)                   │
        └───────────────────────────────────────────────────────────────────────────────────┘
   Объекты-следы: `CSIDriver` (регистрация драйвера), `CSINode` (какие драйверы на ноде),
                  `VolumeAttachment` (факт attach тома к ноде).
```

> **Reality на нашем кластере (Kubespray + local-path):**
> ```bash
> kubectl get csidrivers   # No resources found  — CSI-драйверов НЕТ
> kubectl get csinodes     # у каждой ноды DRIVERS = 0
> kubectl get sc local-path -o jsonpath='{.provisioner}'   # rancher.io/local-path
> ```
> `local-path-provisioner` от Rancher — это **не** CSI-драйвер, а простой
> out-of-tree провижинер: на `CreateVolume` он просто делает `mkdir` каталога на
> ноде (hostPath под капотом) подом-хелпером. Отсюда его ограничения, которые мы
> видим в лабе: **нет** `allowVolumeExpansion` (внешнего resizer не существует) и
> **нет** снапшотов (нет external-snapshotter и CRD VolumeSnapshot). В облаке
> (EBS/PD/Cinder CSI) обе фичи появляются «бесплатно» вместе с CSI-драйвером.

#### Снапшоты томов (VolumeSnapshot — теория, на local-path недоступно)

Где CSI-драйвер умеет снапшоты, точечная копия тома делается тремя объектами:

```yaml
# 1) Класс снапшотов (как StorageClass, но для копий); ставится с CSI-драйвером
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata: { name: csi-snap }
driver: ebs.csi.aws.com          # пример: реальный CSI-драйвер
deletionPolicy: Delete
---
# 2) Запрос снапшота конкретного PVC (в namespace)
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata: { name: data-snap, namespace: lab }
spec:
  volumeSnapshotClassName: csi-snap
  source: { persistentVolumeClaimName: demo-pvc }
# 3) Восстановление: новый PVC с dataSource на этот VolumeSnapshot.
```

> На нашем стенде `kubectl get volumesnapshotclasses` вернёт ошибку «resource type
> not found» — CRD снапшотов в кластер не ставились, т.к. local-path их не
> поддерживает. Это нормально для лабы; раздел — для переноса знаний в облако.

---

**Цель:** пройти весь путь данных `StorageClass → PV → PVC → Pod` и понять, какое
поле где влияет.

**Ресурсы:** `manifests/pvc/pvc.yaml`, `manifests/pvc/consumer.yaml`,
`manifests/static-pv/{pv,pvc}.yaml`

---

### 2.1 Динамическое provisioning: PVC создаёт PV сам

При наличии дефолтного StorageClass достаточно создать PVC — провижинер
**автоматически** создаст соответствующий PV.

```yaml
# manifests/pvc/pvc.yaml — storageClassName не указан => берётся default
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: demo-pvc, namespace: lab }
spec:
  accessModes: [ReadWriteOnce]   # том монтируется на одной ноде на запись
  resources:
    requests: { storage: 1Gi }   # сколько просим
```

```bash
kubectl -n lab apply -f manifests/pvc/pvc.yaml
kubectl -n lab get pvc demo-pvc
```

С `Immediate`-классом PVC сразу `Bound`. С `WaitForFirstConsumer` (k3s/kind):

```
NAME       STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
demo-pvc   Pending                                      local-path     4s
```

```
Events:
  Normal  WaitForFirstConsumer  ... waiting for first consumer to be created before binding
```

Это **нормально** — см. 2.3. Чтобы PVC привязался, нужен Pod-потребитель.

### 2.2 PVC + Pod: привязка и accessModes

`manifests/pvc/consumer.yaml` монтирует `demo-pvc`:

```bash
kubectl -n lab apply -f manifests/pvc/consumer.yaml
kubectl -n lab rollout status deploy/pvc-consumer --timeout=120s

# Теперь PVC привязан — провижинер создал PV под потребителя
kubectl -n lab get pvc demo-pvc
# NAME       STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS
# demo-pvc   Bound    pvc-3f1c...                                1Gi        RWO            local-path

# Посмотреть автоматически созданный PV (кластерный ресурс, без namespace)
kubectl get pv
kubectl -n lab describe pvc demo-pvc | grep -E "Status|Volume:|Used By"
```

**Таблица: accessModes (короткие имена в `kubectl get pv`)**

| Режим | Короткое | Смысл |
|-------|----------|-------|
| `ReadWriteOnce` | RWO | Чтение-запись с **одной ноды** (поды на ней — можно несколько) |
| `ReadOnlyMany` | ROX | Только чтение, с многих нод |
| `ReadWriteMany` | RWX | Чтение-запись с многих нод (нужен NFS/CephFS — не каждый провижинер) |
| `ReadWriteOncePod` | RWOP | Чтение-запись ровно для **одного Pod** (k8s ≥ 1.22) |

> **Частая ошибка:** `RWO` ≠ «один Pod». Это «одна **нода**». Несколько подов на
> одной ноде могут делить RWO-том. Чтобы ограничить ровно одним Pod — `RWOP`.

### 2.3 volumeBindingMode: Immediate vs WaitForFirstConsumer

```bash
kubectl get sc local-path -o jsonpath='{.volumeBindingMode}{"\n"}'
# WaitForFirstConsumer
```

| Режим | Когда PVC → Bound | Зачем |
|-------|-------------------|-------|
| `Immediate` | Сразу после создания PVC | Просто; но PV может оказаться в зоне/на ноде, куда Pod не попадёт |
| `WaitForFirstConsumer` | После появления Pod-потребителя | Том создаётся в той же топологии (зона/нода), что и Pod — критично для зональных дисков и local-storage |

> **Главное практическое следствие:** при `WaitForFirstConsumer` одинокий PVC
> **навсегда останется `Pending`**, если его никто не монтирует. Это типовой
> «висяк» (Инцидент 2) и причина, по которой `manifests/pvc/consumer.yaml`
> добавлен в эту лабу — без него `demo-pvc` не привязался бы.

### 2.4 reclaimPolicy: что станет с PV после удаления PVC

```bash
# Узнать политику у класса (её наследуют динамически созданные PV)
kubectl get sc local-path -o jsonpath='{.reclaimPolicy}{"\n"}'   # Delete
```

| Политика | После `kubectl delete pvc` |
|----------|----------------------------|
| `Delete` | PV и реальный том удаляются вместе с PVC (данные пропадают) |
| `Retain` | PV переходит в `Released`, данные сохраняются, переиспользование — вручную |

```bash
# Демонстрация Retain — на статическом PV (см. 2.5), где политика Retain.
kubectl get pv static-pv-demo -o jsonpath='{.spec.persistentVolumeReclaimPolicy}{"\n"}'
# Retain
```

### 2.5 Статическое provisioning: PV руками

Иногда PV создаёт администратор заранее (NFS-шара, заранее нарезанный диск).
`manifests/static-pv/` показывает это: PV с `storageClassName: manual` и PVC с
тем же классом находят друг друга.

```bash
kubectl apply -f manifests/static-pv/pv.yaml         # PV — кластерный, без -n
kubectl -n lab apply -f manifests/static-pv/pvc.yaml

kubectl get pv static-pv-demo
# NAME             CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                  STORAGECLASS
# static-pv-demo   1Gi        RWO            Retain           Bound    lab/static-pvc-demo    manual

kubectl -n lab get pvc static-pvc-demo
# static-pvc-demo  Bound  static-pv-demo  1Gi  RWO  manual
```

Условия привязки PV↔PVC (все должны совпасть): **тот же `storageClassName`**,
`capacity_PV >= requests_PVC`, совместимые `accessModes`, нет селектора, который
не матчится.

> Удалите PVC при политике `Retain` — PV не исчезнет, а станет `Released`:
> ```bash
> kubectl -n lab delete pvc static-pvc-demo
> kubectl get pv static-pv-demo   # STATUS = Released, данные целы
> # Чтобы переиспользовать PV — убрать .spec.claimRef:
> kubectl patch pv static-pv-demo --type=json -p='[{"op":"remove","path":"/spec/claimRef"}]'
> ```

### 2.6 Расширение тома (online resize)

Расширять том можно, только если у класса `allowVolumeExpansion: true`. Уменьшать
PVC **нельзя** никогда.

```bash
kubectl get sc local-path -o jsonpath='{.allowVolumeExpansion}{"\n"}'
# false  <- у local-path расширение не поддерживается!

# Если класс поддерживает (напр. многие облачные CSI), расширение — это просто
# увеличение запроса в PVC:
kubectl -n lab patch pvc demo-pvc -p '{"spec":{"resources":{"requests":{"storage":"2Gi"}}}}'

# Наблюдать за процессом
kubectl -n lab describe pvc demo-pvc | grep -A3 Conditions
# FileSystemResizePending -> затем размер вырастет (часто без рестарта Pod)
```

> **Грабли:** `local-path` (k3s/kind) **не** умеет expansion (`false`). Команда
> patch пройдёт, но реального роста не будет, а PVC может зависнуть в
> `FileSystemResizePending`. Для практики resize нужен CSI с
> `allowVolumeExpansion: true` (облачные диски, Ceph, OpenEBS и т.п.).

**Контрольные вопросы:**
1. Чем `PV` отличается от `PVC` по области видимости (scope) и роли?
2. Почему при `WaitForFirstConsumer` одинокий PVC висит в `Pending` — это баг?
3. `RWO` — это «один Pod» или «одна нода»? Как ограничить ровно одним Pod?
4. Что произойдёт с данными при `reclaimPolicy: Delete` после удаления PVC? А при `Retain`?
5. Можно ли уменьшить размер PVC? Какое поле класса разрешает увеличение?
6. Как PV и PVC находят друг друга при статическом provisioning?

---

## Часть 3: StatefulSet + volumeClaimTemplates + headless Service

### Теория для изучения перед частью

- Зачем нужен StatefulSet, если есть Deployment: стабильная идентичность
- Стабильное сетевое имя: `<sts>-<ordinal>` и DNS через headless Service
- `volumeClaimTemplates`: отдельный PVC на каждую реплику (имя `<tmpl>-<sts>-<N>`)
- Порядок: упорядоченные создание/удаление/обновление (`OrderedReady`)
- Что происходит с PVC при `scale --replicas=0` и при удалении StatefulSet
- `persistentVolumeClaimRetentionPolicy` (k8s ≥ 1.27)
- Headless Service (`clusterIP: None`) и per-Pod DNS-записи

---

**Цель:** собрать stateful-приложение, у которого каждая реплика имеет свой
постоянный диск и стабильное имя, и убедиться в сохранности данных.

**Ресурсы:** `manifests/statefulset/svc-headless.yaml`, `manifests/statefulset/sts.yaml`

---

### 3.1 Headless Service и стабильные DNS-имена

```yaml
# svc-headless.yaml — clusterIP: None => DNS отдаёт IP каждого Pod напрямую
spec:
  clusterIP: None
  selector: { app: stateful-demo }
```

```bash
kubectl -n lab apply -f manifests/statefulset/svc-headless.yaml
kubectl -n lab get svc stateful-demo-headless
# CLUSTER-IP = None  <- это headless-сервис
```

> Headless-сервис не балансирует трафик и не требует «слушающего» порта — он нужен,
> чтобы DNS создавал записи на каждый Pod:
> `stateful-demo-0.stateful-demo-headless.lab.svc.cluster.local`.

### 3.2 StatefulSet с volumeClaimTemplates

```yaml
# sts.yaml (ключевое)
spec:
  serviceName: stateful-demo-headless   # связь с headless-сервисом
  replicas: 1
  template:
    spec:
      containers:
      - name: app
        image: busybox:1.36
        command: ["sh","-c","while true; do date >> /data/time.log; sleep 5; done"]
        volumeMounts: [{ name: data, mountPath: /data }]
  volumeClaimTemplates:        # НЕ volumes! Шаблон PVC на каждую реплику
  - metadata: { name: data }
    spec:
      accessModes: [ReadWriteOnce]
      resources: { requests: { storage: 1Gi } }
```

```bash
kubectl -n lab apply -f manifests/statefulset/sts.yaml
kubectl -n lab rollout status statefulset/stateful-demo --timeout=120s

# Имя Pod детерминировано: <sts>-<ordinal>
kubectl -n lab get pods -l app=stateful-demo
# stateful-demo-0   1/1   Running

# Для каждой реплики создан ОТДЕЛЬНЫЙ PVC с именем <template>-<sts>-<ordinal>
kubectl -n lab get pvc -l app=stateful-demo
# data-stateful-demo-0   Bound   pvc-...   1Gi   RWO   local-path
```

> Сравните с Deployment: там все реплики делят (или не имеют) общий PVC, а имена
> подов случайны (`<rs-hash>-<rand>`). У StatefulSet — фиксированное имя и свой диск.

### 3.3 Сохранность данных при пересоздании Pod

```bash
# Запишем маркер в постоянный том реплики 0
kubectl -n lab exec stateful-demo-0 -- sh -c 'echo PERSIST-OK > /data/marker.txt'

# Удалим Pod. StatefulSet пересоздаст его с ТЕМ ЖЕ именем и ТЕМ ЖЕ PVC
kubectl -n lab delete pod stateful-demo-0
kubectl -n lab wait --for=condition=Ready pod/stateful-demo-0 --timeout=120s

# Данные на месте — PVC пережил пересоздание Pod
kubectl -n lab exec stateful-demo-0 -- cat /data/marker.txt
# PERSIST-OK
```

### 3.4 Масштабирование и судьба PVC

```bash
# Увеличим до 3 реплик — у каждой появится свой PVC
kubectl -n lab scale statefulset/stateful-demo --replicas=3
kubectl -n lab rollout status statefulset/stateful-demo --timeout=180s
kubectl -n lab get pvc -l app=stateful-demo
# data-stateful-demo-0/1/2  <- три отдельных тома

# Уменьшим обратно до 1 — лишние ПОДЫ удалятся, а PVC ОСТАНУТСЯ
kubectl -n lab scale statefulset/stateful-demo --replicas=1
kubectl -n lab get pods -l app=stateful-demo   # остался stateful-demo-0
kubectl -n lab get pvc   -l app=stateful-demo  # data-...-1 и -2 ВСЁ ЕЩЁ ЕСТЬ
```

> **Это by design:** при scale down StatefulSet не удаляет PVC, чтобы не потерять
> данные. Чистить их нужно вручную (`kubectl delete pvc data-stateful-demo-2`) или
> настроить `persistentVolumeClaimRetentionPolicy` (k8s ≥ 1.27):
> ```yaml
> spec:
>   persistentVolumeClaimRetentionPolicy:
>     whenScaled: Delete      # удалять PVC при scale down
>     whenDeleted: Retain     # но сохранять при удалении самого StatefulSet
> ```

**Таблица: Deployment vs StatefulSet для хранилища**

| Свойство | Deployment | StatefulSet |
|----------|-----------|-------------|
| Имена подов | Случайные | Стабильные (`name-0,1,2`) |
| Том на реплику | Общий/нет | Свой PVC (`volumeClaimTemplates`) |
| Порядок создания/удаления | Параллельно | Упорядоченно (0→1→2) |
| DNS на конкретный Pod | Нет | Да (через headless) |
| PVC при scale down | — | Сохраняется |
| Применение | stateless (web, API) | БД, очереди, кворумные системы |

**Контрольные вопросы:**
1. Как формируется имя PVC, созданного из `volumeClaimTemplates`?
2. Почему у StatefulSet `serviceName` указывает на headless-сервис?
3. Что произойдёт с данными, если удалить `stateful-demo-0`? Почему?
4. Куда денутся PVC при `scale --replicas=3 → 1`? Как это изменить?
5. Чем DNS-имя пода StatefulSet отличается от обычного Pod за ClusterIP-сервисом?

---

## Часть 4: Troubleshooting — боевые инциденты

### Теория для изучения перед частью

- Фазы PVC (`Pending`/`Bound`/`Lost`) и где смотреть причину (`describe`, events)
- Цепочка монтирования: `PVC Bound → attach к ноде → mount в Pod`
- Сообщения `FailedScheduling`, `FailedAttachVolume`, `FailedMount`, `Multi-Attach`
- Чем `ProvisioningFailed` (нет провижинера) отличается от `WaitForFirstConsumer`
- Почему RWO-том нельзя примонтировать на две ноды сразу
- Связь `df` внутри контейнера и реального размера PV

#### Алгоритм диагностики storage по симптому

Storage-сбой проявляется либо как «PVC не Bound», либо как «Pod застрял на томе».
Ветвись по тому, что застряло:

```
Pod не стартует / том не работает
│
├─ PVC в Pending ? ──────► kubectl describe pvc <pvc>  → блок Events:
│     ├─ "storageclass ... not found"          → класса нет/опечатка; PVC иммутабелен → пересоздать (Инцидент 1)
│     ├─ "waiting for first consumer"          → НЕ ошибка: WaitForFirstConsumer ждёт Pod (Инцидент 2)
│     ├─ "ProvisioningFailed" (квота/бэкенд)   → провижинер есть, но создать том не смог (квота/право/диск)
│     └─ нет подходящего Available PV (статика) → проверь матчинг: класс/accessModes/capacity/selector
│
├─ PVC Bound, но Pod в ContainerCreating ? ──► kubectl describe pod <pod>  → Events:
│     ├─ "FailedAttachVolume / Multi-Attach"   → RWO-том уже на другой ноде (Инцидент 3); жди отцепления старого Pod
│     ├─ "FailedMount ... timeout"             → нода не может смонтировать: CSI node-plugin/драйвер ФС/сеть к СХД
│     └─ "MountVolume.SetUp failed: not found" → секрет/ConfigMap тома нет (для projected-томов, → м07/м16)
│
├─ Pod Running, но "No space left on device" ► том заполнен: df внутри Pod (kubectl exec -- df -h /path);
│     │                                          расширить PVC (если allowVolumeExpansion=true) или чистить
│     └─ на local-path расширение НЕ поддержано → пересоздать том большего размера + перенос данных
│
└─ Данные пропали после рестарта ? ──────────► том эфемерный (emptyDir) или hostPath на другой ноде —
                                                нужен PVC/StatefulSet (Часть 1.2 vs Часть 3.3)
```

Опорные команды: `kubectl get pvc,pv` (фазы), `describe pvc/pod` (Events — главный
источник причины), `kubectl get volumeattachment` (факт attach к ноде), `exec -- df -h`.

---

**Цель:** отработать диагностику типовых storage-сбоев по схеме
**Воспроизведение → Диагностика → Решение → Профилактика**.

---

### Инцидент 1: PVC висит в Pending — несуществующий StorageClass

Готовая поломка: `broken/scenario-01/` (PVC ссылается на класс `does-not-exist`,
Deployment `storage-demo` его монтирует и потому не стартует).

**Воспроизведение:**

```bash
kubectl -n lab apply -f broken/scenario-01/pvc.yaml
kubectl -n lab apply -f broken/scenario-01/deploy.yaml
kubectl -n lab get pods -l app=storage-demo
# storage-demo-...   0/1   Pending   <- Pod не стартует
```

**Диагностика:**

```bash
# 1) Статус PVC — Pending
kubectl -n lab get pvc demo-pvc
# demo-pvc   Pending   ...   does-not-exist

# 2) Причина — в events PVC
kubectl -n lab describe pvc demo-pvc | sed -n '/Events/,$p'
# Warning  ProvisioningFailed  storageclass.storage.k8s.io "does-not-exist" not found
#   ^ провижинера для такого класса нет

# 3) Pod ждёт том
kubectl -n lab describe pod -l app=storage-demo | grep -A3 Events
# Warning  FailedScheduling  ... persistentvolumeclaim "demo-pvc" not bound

# Какие классы реально есть?
kubectl get sc
```

**Решение:**

```bash
# PVC иммутабелен по storageClassName — пересоздаём с верным (пустым => default) классом
kubectl -n lab delete pvc demo-pvc --ignore-not-found
kubectl -n lab apply -f solutions/01-pvc-pending/pvc.yaml   # без storageClassName
kubectl -n lab rollout status deploy/storage-demo --timeout=120s
kubectl -n lab get pvc demo-pvc   # Bound
```

**Профилактика:**
- Не хардкодить имя класса; полагаться на default или валидировать его наличие в CI.
- Admission-политикой (Kyverno/Gatekeeper) запрещать PVC со ссылкой на несуществующий класс.

### Инцидент 2: PVC Pending, хотя StorageClass есть (WaitForFirstConsumer)

Самый частый «ложный» висяк на k3s/kind.

**Воспроизведение:**

```bash
# Создаём ТОЛЬКО PVC, без пода-потребителя
cat <<'EOF' | kubectl -n lab apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: lonely-pvc, namespace: lab }
spec:
  accessModes: [ReadWriteOnce]
  resources: { requests: { storage: 1Gi } }
EOF

kubectl -n lab get pvc lonely-pvc
# lonely-pvc   Pending   ...   local-path
```

**Диагностика:**

```bash
kubectl -n lab describe pvc lonely-pvc | sed -n '/Events/,$p'
# Normal  WaitForFirstConsumer  waiting for first consumer to be created before binding
#   ^ это НЕ ошибка: класс ждёт Pod, чтобы выбрать топологию тома
kubectl get sc local-path -o jsonpath='{.volumeBindingMode}{"\n"}'   # WaitForFirstConsumer
```

**Решение:**

```bash
# Дать PVC потребителя — и он мгновенно привяжется.
# (нужен Pod, монтирующий именно lonely-pvc; здесь просто очищаем демонстрацию)
kubectl -n lab delete pvc lonely-pvc
```

**Профилактика:**
- Понимать, что одинокий PVC при WFC — это норма, а не сбой; не «чинить» его рестартами.
- Если нужна немедленная привязка (Immediate) — завести класс с `volumeBindingMode: Immediate`.

### Инцидент 3: Pod не стартует — Multi-Attach error (RWO на двух нодах)

> **Только многонодовый кластер.** На одной ноде не воспроизводится.

**Воспроизведение:** готовая поломка в `broken/scenario-02/` — Deployment с
`replicas: 2`, общим RWO-PVC и anti-affinity, раскидывающим поды по нодам.

> ⚠️ Проявление зависит от провижинера. На облачных CSI-драйверах блочных
> дисков — `Multi-Attach error` (ниже). На нашем local-path том привязан к ноде
> через `nodeAffinity` PV, поэтому второй под висит в `Pending` с
> `didn't match PersistentVolume's node affinity` — см. README сценария; там же
> разобран deadlock «RollingUpdate + RWO» и зачем нужен `strategy: Recreate`.

**Диагностика:**

```bash
kubectl -n lab describe pod <второй-под> | grep -A2 Events
# Warning  FailedAttachVolume  Multi-Attach error for volume "pvc-..."
#          Volume is already exclusively attached to one node and can't be attached to another
```

**Решение / правильный паттерн:**
- Для «много реплик, у каждой свой диск» — **StatefulSet** с `volumeClaimTemplates` (Часть 3), а не Deployment с общим RWO.
- Для реально общего тома между нодами — `accessMode: RWX` и провижинер, который его умеет (NFS/CephFS); local-path этого не умеет.

**Профилактика:** не масштабировать Deployment с общим RWO-томом выше 1 реплики;
для shared-состояния явно выбирать RWX или внешнее хранилище.

### Бонус: общая диагностика storage

```bash
# Все PVC и их фазы по кластеру
kubectl get pvc -A

# Все PV: статус, к какому PVC привязаны и политика reclaim
kubectl get pv -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,CLAIM:.spec.claimRef.name,RECLAIM:.spec.persistentVolumeReclaimPolicy,SC:.spec.storageClassName'

# Свежие события, связанные с томами
kubectl -n lab get events --sort-by=.lastTimestamp | grep -Ei 'volume|pvc|mount|attach|provision' | tail -20

# Реальный размер тома и заполнение — изнутри Pod
kubectl -n lab exec deploy/pvc-consumer -- df -h /data

# Кто использует PVC (поле Used By)
kubectl -n lab describe pvc demo-pvc | grep -A2 "Used By"
```

**Контрольные вопросы:**
1. Чем `ProvisioningFailed` отличается от события `WaitForFirstConsumer`?
2. По каким двум объектам (и их events) диагностируется «Pod в Pending из-за тома»?
3. Что означает `Multi-Attach error` и какой workload его обычно вызывает?
4. Почему `storageClassName` нельзя «поправить» в существующем PVC?
5. Как переиспользовать `Released` PV после удаления PVC при политике `Retain`?

---

## Проверка модуля

```bash
# Сначала разверните рабочие манифесты (а не broken-вариант)
kubectl -n lab apply -k manifests/
kubectl -n lab rollout status deploy/pvc-consumer --timeout=120s
kubectl -n lab rollout status statefulset/stateful-demo --timeout=120s

# Автопроверка
bash verify/verify.sh
```

`verify/verify.sh` проверяет: наличие StorageClass, `demo-pvc` в статусе `Bound`,
headless-сервис, готовность StatefulSet и наличие `volumeClaimTemplates`.

> Если `demo-pvc` остаётся `Pending` — почти наверняка класс с
> `WaitForFirstConsumer` и не применён `pvc/consumer.yaml` (Инцидент 2).

---

## Финальная карта ресурсов модуля

| Ресурс | Часть | Что демонстрирует |
|--------|-------|-------------------|
| `storage-emptydir` (Pod) | 1 | emptyDir: общий том, жизнь = жизнь Pod |
| `storage-hostpath` (Pod) | 1 | hostPath: привязка к ноде, риски |
| `demo-pvc` (PVC) + `pvc-consumer` (Deploy) | 2 | Динамическое provisioning, Bound через потребителя |
| `static-pv-demo` (PV) + `static-pvc-demo` (PVC) | 2 | Статическое provisioning, `Retain`, класс `manual` |
| `stateful-demo` (StatefulSet) + `data-stateful-demo-N` (PVC) | 3 | Стабильная идентичность + диск на реплику |
| `stateful-demo-headless` (Service) | 3 | Headless-сервис, per-Pod DNS |
| `broken/scenario-01` (`demo-pvc` + `storage-demo`) | 4 | Инцидент: несуществующий StorageClass |

---

## Теоретические вопросы (итоговые)

### Блок 1: Тома и жизненный цикл данных
1. Перечислите уровни жизни данных в k8s (контейнер → Pod → нода → кластер) и сопоставьте с типами томов.
2. Почему `emptyDir` нельзя использовать для БД, даже если приложение «вроде работает»?
3. В каких сценариях `hostPath` оправдан, несмотря на риски? (Подсказка: DaemonSet-агенты.)

### Блок 2: PV/PVC/StorageClass
4. Опишите полный путь динамического provisioning от `kubectl apply -f pvc.yaml` до смонтированного тома.
5. Чем статическое provisioning отличается от динамического? Кто создаёт PV в каждом случае?
6. Что произойдёт с PVC без `storageClassName`, если в кластере нет дефолтного класса?
7. Зачем нужен `WaitForFirstConsumer` и какую проблему `Immediate` он решает на зональных кластерах?
8. Сравните `reclaimPolicy: Delete` и `Retain` с точки зрения сохранности данных и операционных рисков.

### Блок 3: accessModes и многонодовость
9. Почему `ReadWriteOnce` — это «одна нода», а не «один Pod»? Когда нужен `ReadWriteOncePod`?
10. Какой `accessMode` нужен, чтобы один том писали поды с разных нод, и что для этого требуется от провижинера?
11. Опишите механику ошибки `Multi-Attach` и как её избежать архитектурно.

### Блок 4: StatefulSet
12. Чем StatefulSet принципиально отличается от Deployment по идентичности и хранилищу?
13. Как именуются PVC из `volumeClaimTemplates` и почему это важно для восстановления состояния?
14. Что происходит с PVC при scale down и при удалении StatefulSet? Как управлять этим в k8s ≥ 1.27?
15. Зачем StatefulSet нужен headless Service?

### Блок 5: Troubleshooting
16. PVC в `Pending`. Назовите минимум три разные причины и команду диагностики для каждой.
17. Pod застрял в `ContainerCreating` с `FailedMount`. Куда смотреть и какова типовая первопричина?
18. Можно ли изменить `storageClassName` или уменьшить размер у существующего PVC? Почему?
19. Как безопасно «вернуть в строй» `Released` PV без потери данных?
20. Как изнутри Pod проверить реальный размер и заполнение примонтированного PV?

---



## Чему вы научились

В этом модуле вы научились:
- Разнице между ephemeral хранилищами (emptyDir) и постоянными (PV/PVC)
- Динамическому выделению хранилища через StorageClass
- Подключению блочных дисков к StatefulSet

## Уборка

Очистите ресурсы после завершения:
```bash
../../scripts/clean/clean-module.sh modules/05-storage
```

## Практические задания (отработка)

> Делайте на живом кластере; проверяйте себя командами и `verify/verify.sh`.

1. Создайте PVC без `storageClassName` и убедитесь, что он связался дефолтным классом (`WaitForFirstConsumer` — нужен под-потребитель).
2. Воспроизведите PVC `Pending` (несуществующий StorageClass), найдите причину в событиях, почините.
3. StatefulSet: масштабируйте вниз и убедитесь, что PVC реплик НЕ удаляются (orphan-защита); удалите их вручную.
4. Статический PV+PVC с `storageClassName: manual` — добейтесь `Bound`, объясните условия связывания.
5. Запишите файл в смонтированный том, пересоздайте под, проверьте, что данные на месте.

---

## Шпаргалка

```bash
# === Обзор ===
kubectl get sc                                  # классы хранения и default
kubectl get pv                                  # тома (кластерные)
kubectl -n lab get pvc                          # запросы на тома (в namespace)
kubectl -n lab describe pvc <name>              # причина Pending — в Events

# === Свойства класса (определяют половину поведения) ===
kubectl get sc <sc> -o jsonpath='{.volumeBindingMode}{"\n"}'      # Immediate|WaitForFirstConsumer
kubectl get sc <sc> -o jsonpath='{.reclaimPolicy}{"\n"}'          # Delete|Retain
kubectl get sc <sc> -o jsonpath='{.allowVolumeExpansion}{"\n"}'   # true|false

# === PVC: создать / расширить (если класс позволяет) ===
kubectl -n lab apply -f manifests/pvc/pvc.yaml
kubectl -n lab patch pvc <name> -p '{"spec":{"resources":{"requests":{"storage":"2Gi"}}}}'

# === Статический PV ===
kubectl apply -f manifests/static-pv/pv.yaml    # PV без -n (кластерный)
kubectl -n lab apply -f manifests/static-pv/pvc.yaml
kubectl patch pv <pv> --type=json -p='[{"op":"remove","path":"/spec/claimRef"}]'  # переиспользовать Released

# === StatefulSet + тома ===
kubectl -n lab apply -f manifests/statefulset/svc-headless.yaml
kubectl -n lab apply -f manifests/statefulset/sts.yaml
kubectl -n lab get pods,pvc -l app=stateful-demo
kubectl -n lab scale statefulset/stateful-demo --replicas=3

# === Эфемерные тома ===
kubectl -n lab apply -f manifests/emptydir/pod.yaml
kubectl -n lab apply -f manifests/hostpath/pod.yaml

# === Диагностика ===
kubectl get pv -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,CLAIM:.spec.claimRef.name,RECLAIM:.spec.persistentVolumeReclaimPolicy'
kubectl -n lab get events --sort-by=.lastTimestamp | grep -Ei 'volume|pvc|mount|attach|provision'
kubectl -n lab exec deploy/pvc-consumer -- df -h /data
```
