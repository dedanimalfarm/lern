# Лабораторная работа 29: Жизненный цикл пода v2 — native sidecars, scheduling gates, in-place resize

## Оглавление
<!-- TOC -->
- [Предварительные требования](#предварительные-требования)
- [Стартовая проверка](#стартовая-проверка)
- [Часть 1: Native sidecar-контейнеры (GA 1.33)](#часть-1-native-sidecar-контейнеры-ga-133)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью)
  - [1.1 История проблемы: как sidecar ломали Job](#11-история-проблемы-как-sidecar-ломали-job)
  - [1.2 Job с native sidecar в действии](#12-job-с-native-sidecar-в-действии)
  - [1.3 Жизненный цикл и порядок остановки контейнеров](#13-жизненный-цикл-и-порядок-остановки-контейнеров)
  - [1.4 Взаимодействие sidecar с readiness и liveness пробами](#14-взаимодействие-sidecar-с-readiness-и-liveness-пробами)
- [Часть 2: Scheduling gates — отложенный старт (GA 1.30)](#часть-2-scheduling-gates--отложенный-старт-ga-130)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-1)
  - [2.1 Gated под и снятие gate](#21-gated-под-и-снятие-gate)
  - [2.2 Использование нескольких scheduling gates](#22-использование-нескольких-scheduling-gates)
  - [2.3 Почему не initContainers? (Сравнение подходов)](#23-почему-не-initcontainers-сравнение-подходов)
  - [2.4 Интеграция с Kueue и пакетными нагрузками](#24-интеграция-с-kueue-и-пакетными-нагрузками)
- [Часть 3: In-place Pod resize — вертикальный скейл без рестарта (beta 1.33)](#часть-3-in-place-pod-resize--вертикальный-скейл-без-рестарта-beta-133)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-2)
  - [3.1 Resize без рестарта (reality на нашем кластере)](#31-resize-без-рестарта-reality-на-нашем-кластере)
  - [3.2 Механика работы resizePolicy: NotRequired vs RestartContainer](#32-механика-работы-resizepolicy-notrequired-vs-restartcontainer)
  - [3.3 Поймать обе валидации (ограничения QoS и limit)](#33-поймать-обе-валидации-ограничения-qos-и-limit)
  - [3.4 Как kubelet обновляет cgroups](#34-как-kubelet-обновляет-cgroups)
  - [3.5 Статус subresource resize и фазы применения](#35-статус-subresource-resize-и-фазы-применения)
- [Часть 4: Troubleshooting — боевые инциденты](#часть-4-troubleshooting--боевые-инциденты)
  - [Теория: алгоритм диагностики по симптому](#теория-алгоритм-диагностики-по-симптому)
  - [Инцидент 1: Job не завершается (sidecar-антипаттерн)](#инцидент-1-job-не-завершается-sidecar-антипаттерн)
  - [Инцидент 2: Под завис в Pending из-за забытого Gate](#инцидент-2-под-завис-в-pending-из-за-забытого-gate)
  - [Инцидент 3: In-place resize отбит: нарушение QoS-класса](#инцидент-3-in-place-resize-отбит-нарушение-qos-класса)
  - [Бонус: общая диагностика Pod lifecycle](#бонус-общая-диагностика-pod-lifecycle)
- [Проверка модуля](#проверка-модуля)
- [Финальная карта ресурсов модуля](#финальная-карта-ресурсов-модуля)
- [Теоретические вопросы (итоговые)](#теоретические-вопросы-итоговые)
  - [Блок 1: Native sidecar](#блок-1-native-sidecar)
  - [Блок 2: Scheduling gates](#блок-2-scheduling-gates)
  - [Блок 3: In-place resize](#блок-3-in-place-resize)
  - [Блок 4: Troubleshooting](#блок-4-troubleshooting)
- [Архитектурные нюансы и глубокое погружение (Deep Dive)](#архитектурные-нюансы-и-глубокое-погружение-deep-dive)
  - [1. Почему Resize CPU работает без рестарта, а Memory часто требует рестарта?](#1-почему-resize-cpu-работает-без-рестарта-а-memory-часто-требует-рестарта)
  - [2. Роль Container Runtime Interface (CRI) в In-place Resize](#2-роль-container-runtime-interface-cri-в-in-place-resize)
  - [3. Взаимодействие Scheduling Gates и Cluster Autoscaler](#3-взаимодействие-scheduling-gates-и-cluster-autoscaler)
  - [4. Native Sidecars и Service Mesh (Istio / Envoy)](#4-native-sidecars-и-service-mesh-istio--envoy)
  - [5. Лимиты на изменения ресурсов](#5-лимиты-на-изменения-ресурсов)
  - [6. Взаимодействие In-place Resize с Horizontal Pod Autoscaler (HPA) и Vertical Pod Autoscaler (VPA)](#6-взаимодействие-in-place-resize-с-horizontal-pod-autoscaler-hpa-и-vertical-pod-autoscaler-vpa)
- [Часто Задаваемые Вопросы (FAQ) и Продвинутые Сценарии](#часто-задаваемые-вопросы-faq-и-продвинутые-сценарии)
  - [Вопрос 1: Что произойдет, если OOM Killer убьет Native Sidecar?](#вопрос-1-что-произойдет-если-oom-killer-убьет-native-sidecar)
  - [Вопрос 2: Как Native Sidecar влияет на расчет ресурсов пода (Requests/Limits)?](#вопрос-2-как-native-sidecar-влияет-на-расчет-ресурсов-пода-requestslimits)
  - [Вопрос 3: Как работает In-place Resize с Pod Disruption Budgets (PDB)?](#вопрос-3-как-работает-in-place-resize-с-pod-disruption-budgets-pdb)
  - [Вопрос 4: Как Scheduling Gates защищают от "Thunder Herd" (Эффекта толпы)?](#вопрос-4-как-scheduling-gates-защищают-от-thunder-herd-эффекта-толпы)
  - [Вопрос 5: Можно ли использовать In-place resize для изменения Request до значений, превышающих Capacity ноды?](#вопрос-5-можно-ли-использовать-in-place-resize-для-изменения-request-до-значений-превышающих-capacity-ноды)
  - [Вопрос 6: В каких случаях стоит избегать Native Sidecars?](#вопрос-6-в-каких-случаях-стоит-избегать-native-sidecars)
- [Архитектурные антипаттерны: Чего делать не следует](#архитектурные-антипаттерны-чего-делать-не-следует)
  - [1. Подмена readinessProbe с помощью Scheduling Gates](#1-подмена-readinessprobe-с-помощью-scheduling-gates)
  - [2. Использование In-place resize как замены HPA](#2-использование-in-place-resize-как-замены-hpa)
  - [3. Native Sidecar для бизнес-логики](#3-native-sidecar-для-бизнес-логики)
- [Чему вы научились](#чему-вы-научились)
- [Эволюция жизненного цикла пода (History & Evolution)](#эволюция-жизненного-цикла-пода-history--evolution)
  - [До Kubernetes 1.28: Эпоха костылей](#до-kubernetes-128-эпоха-костылей)
  - [Kubernetes 1.28 - 1.29: Появление надежды](#kubernetes-128---129-появление-надежды)
  - [Kubernetes 1.30+: Зрелость (GA)](#kubernetes-130-зрелость-ga)
- [Взаимодействие фич между собой](#взаимодействие-фич-между-собой)
- [Резюме лучших практик (Best Practices)](#резюме-лучших-практик-best-practices)
- [Уборка](#уборка)
- [Практические задания (отработка)](#практические-задания-отработка)
- [Шпаргалка](#шпаргалка)
<!-- /TOC -->

> ⏱ время ~45 мин · сложность 3/5 · пререквизиты: модули 02, 12

---

Цель: глубоко освоить ТРИ современные возможности API пода (все GA/beta в свежих версиях Kubernetes), которые кардинально меняют повседневные паттерны платформ: **native sidecar-контейнеры** (GA 1.33), **scheduling gates** (GA 1.30) и **in-place Pod resize** (beta 1.33).

К концу этого модуля вы научитесь:
1. Делать лог-/прокси-агент корректным sidecar-контейнером, который не мешает завершению Job.
2. Откладывать старт пода до получения внешнего сигнала (без потребления ресурсов на busy-wait).
3. Изменять выделенные ресурсы (CPU/Memory) работающему поду на лету, избегая его пересоздания и перебоев в обслуживании.
4. Понимать архитектурные ограничения каждой фичи и уметь диагностировать возникающие проблемы.

> Эта работа является логическим развитием модуля 02 (жизненный цикл подов, sidecar-таблица) и модуля 12 (QoS-классы и масштабирование ресурсов). Здесь мы переходим от теории к практике новых API на живом кластере. Все «ожидаемые выводы» протестированы на нашем стенде Kubespray (k8s v1.36.1) — фичи доступны штатно, так как наш сервер удовлетворяет требованиям версий (sidecar GA 1.33, gates GA 1.30, resize beta 1.33).

---

## Предварительные требования

Для успешного выполнения лабораторной работы вам потребуется доступ к кластеру Kubernetes версии 1.33 или выше (для поддержки всех описанных фич). На нашем стенде (Kubespray) эти условия уже выполнены.

Выполните следующие команды для подготовки окружения:

```bash
# Устанавливаем kubeconfig нашего кластера (Kubespray). 
# Если вы работаете на другом стенде — используйте свой путь или контекст.
export KUBECONFIG=/root/.kube/kubespray.conf

# Создаем namespace для лабораторной работы, если он еще не существует
kubectl create ns lab --dry-run=client -o yaml | kubectl apply -f -

# Очищаем namespace от предыдущих запусков
kubectl -n lab delete job,pod --all --ignore-not-found 2>/dev/null

# Проверяем версию сервера (убеждаемся, что фичи доступны)
kubectl version -o json | grep -A3 '"serverVersion"' | grep gitVersion
# Ожидаемый вывод: "v1.36.1" или любая версия >= 1.33
# (grep -m1 показал бы версию КЛИЕНТА kubectl, а не сервера)

# Настраиваем удобный алиас
alias k='kubectl -n lab'
```

Обратите внимание: признаком активного in-place resize является наличие поля `allocatedResources` в статусе контейнера у запущенного пода (мы подробно рассмотрим это в Части 3).

---

## Стартовая проверка

Перед началом убедимся, что кластер чист от конфликтующих ресурсов в нашем namespace:

```bash
kubectl -n lab get job,pod 2>&1 | head -1
# Вывод должен быть пустым (No resources found in lab namespace)
```

> **Важно:** Эти три фичи (Native sidecars, Scheduling gates, In-place resize) встроены в ядро Kubernetes. Они **НЕ требуют** установки дополнительных контроллеров, CRD, аддонов или CSI-драйверов. Вся магия происходит на уровне `kube-apiserver`, `kube-scheduler` и `kubelet`.

---

## Часть 1: Native sidecar-контейнеры (GA 1.33)

### Теория для изучения перед частью

- **Sidecar-паттерн** — это архитектурный шаблон, при котором вспомогательный контейнер (sidecar) развертывается в одном поде с основным приложением (app). Sidecar делит с основным контейнером одни и те же namespaces (network, IPC, иногда PID) и тома. Типичные примеры: лог-шипперы (fluentd, filebeat), service-mesh прокси (Envoy, Linkerd), vault-агенты, сборщики метрик.
- **Проблема старого подхода:** До версии 1.28 sidecar-контейнеры помещались в массив `containers[]`. Из-за этого в объектах типа `Job` возникала фундаментальная проблема. Job считается выполненным (Complete) только когда завершаются **все** контейнеры. Но sidecar (например, лог-шиппер) обычно работает бесконечно. В итоге основное приложение завершало работу, а sidecar продолжал работать. Под зависал в статусе `NotReady (1/2)`, а Job оставался `Active` навсегда.
- **Решение — Native sidecar:** В новых версиях Kubernetes появился встроенный (нативный) механизм. Теперь sidecar объявляется в массиве `initContainers`, но с особым параметром `restartPolicy: Always`.

**Ключевые отличия native sidecar от обычного init-контейнера и от обычного контейнера:**
1. **Не блокирует запуск:** В отличие от стандартного init-контейнера, который должен успешно завершиться (`Completed`) перед запуском основных контейнеров, native sidecar блокирует запуск основных контейнеров только до момента своей готовности (перехода в статус `Started` или успешного прохождения readiness-пробы).
2. **Живет весь цикл:** В отличие от обычных init-контейнеров, native sidecar продолжает работать параллельно с основными контейнерами на протяжении всего жизненного цикла пода.
3. **Корректное завершение:** Kubelet гасит native sidecars **ПОСЛЕ** завершения всех основных контейнеров (обратный порядок). Это гарантирует, что прокси или лог-шиппер не выключится раньше, чем основное приложение успеет отправить последние логи или сетевые запросы.
4. **Совместимость с Job:** При использовании в Job, kubelet автоматически завершит native sidecar, как только завершатся все основные контейнеры. Job успешно перейдет в статус `Complete`.

### 1.1 История проблемы: как sidecar ломали Job

Давайте представим, что мы живем в 2021 году и пытаемся запустить пакетную задачу, которая пишет логи в файл, а sidecar отправляет их в центральное хранилище. Если мы поместим оба контейнера в `containers[]`, произойдет следующее:

1. Основной контейнер отрабатывает за 5 секунд и выходит с кодом 0 (успех).
2. Лог-шиппер (например, `fluent-bit`) продолжает работать (он слушает изменения файла через `tail -f`).
3. Под переходит в состояние, где 1 контейнер `Completed`, а 1 — `Running`.
4. Контроллер Job видит, что под еще работает, и не отмечает Job как выполненный.
5. Ресурс зависает навечно (или до достижения `activeDeadlineSeconds`).

Разработчикам приходилось придумывать сложные «костыли»: писать wrapper-скрипты, передавать сигналы через общие тома (`emptyDir`), использовать HTTP-эндпоинты для принудительного убийства sidecar'а из основного контейнера. Native sidecar делает все это ненужным.

### 1.2 Job с native sidecar в действии

Перейдем к практике. Развернем Job, который использует новый нативный подход.

**Цель:** Запустить Job с лог-шиппером, который корректно завершится после отработки основного приложения.

Посмотрим на манифест `manifests/sidecar/job.yaml`:
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: sidecar-job
  namespace: lab
spec:
  template:
    spec:
      restartPolicy: Never
      initContainers:
      - name: logshipper
        image: busybox:1.36
        restartPolicy: Always   # <--- МАГИЯ NATIVE SIDECAR
        command: ["sh", "-c", "tail -F /var/log/app.log"]
        volumeMounts:
        - name: logs
          mountPath: /var/log
      containers:
      - name: app
        image: busybox:1.36
        command: ["sh", "-c", "echo 'Work started'; sleep 5; echo 'Work done' >> /var/log/app.log; exit 0"]
        volumeMounts:
        - name: logs
          mountPath: /var/log
      volumes:
      - name: logs
        emptyDir: {}
```

Обратите внимание: `logshipper` определен внутри `initContainers`, и у него явно проставлен `restartPolicy: Always`.

```bash
# Применяем манифест
kubectl -n lab apply -f manifests/sidecar/job.yaml

# Наблюдаем за подом. Вы увидите, что сначала стартует init,
# затем app. Под переходит в Running (2/2).
kubectl -n lab get pod -l job-name=sidecar-job -w

# Ожидаемый вывод:
# sidecar-job-xxxxx   0/2   Pending     0   0s
# sidecar-job-xxxxx   0/2   Init:0/1    0   1s
# sidecar-job-xxxxx   1/2   Running     0   2s   <- sidecar запущен
# sidecar-job-xxxxx   2/2   Running     0   3s   <- app запущен
# sidecar-job-xxxxx   1/2   NotReady    0   8s   <- app завершился (Completed)
# sidecar-job-xxxxx   0/2   Completed   0   9s   <- sidecar корректно остановлен
```

Убедимся, что Job успешно выполнился:

```bash
kubectl -n lab wait --for=condition=complete job/sidecar-job --timeout=60s
kubectl -n lab get job sidecar-job
```

```text
NAME          STATUS     COMPLETIONS   DURATION   AGE
sidecar-job   Complete   1/1           9s         12s
```

Подтвердим, что контейнер действительно сконфигурирован как нативный sidecar:

```bash
kubectl -n lab get job sidecar-job \
  -o jsonpath='Container: {.spec.template.spec.initContainers[0].name}, RestartPolicy: {.spec.template.spec.initContainers[0].restartPolicy}{"\n"}'
# Вывод: Container: logshipper, RestartPolicy: Always
```

### 1.3 Жизненный цикл и порядок остановки контейнеров

Порядок запуска и остановки — важнейшая часть дизайна native sidecars.
Kubelet гарантирует следующий флоу:
1. Запускаются обычные `initContainers` (по очереди, дожидаясь `Completed`).
2. Запускается `initContainer` с `restartPolicy: Always` (наш sidecar).
3. Kubelet дожидается, когда sidecar перейдет в состояние `Started` (или пройдет `startupProbe`, если она задана).
4. Запускаются основные контейнеры `containers[]`.

При остановке (или когда Job завершает работу):
1. Kubelet посылает SIGTERM основным контейнерам.
2. Только после полного завершения ВСЕХ основных контейнеров, kubelet посылает SIGTERM нашему native sidecar.
3. Это дает sidecar-контейнеру (например, service-mesh прокси) время обработать последние исходящие запросы от завершающегося приложения, или дослать последние строчки логов.

### 1.4 Взаимодействие sidecar с readiness и liveness пробами

Native sidecars полностью поддерживают все типы проб (`startup`, `readiness`, `liveness`).
- Если у sidecar настроена `readinessProbe`, он не будет считаться готовым, пока проба не пройдет. Это напрямую влияет на общую readiness пода (под не получит трафик от Service, если его sidecar не ready).
- Если `livenessProbe` sidecar'а падает, он будет перезапущен политикой `Always`, независимо от того, что происходит с основными контейнерами.

---

## Часть 2: Scheduling gates — отложенный старт (GA 1.30)

### Теория для изучения перед частью

- **`schedulingGates`** — это концепция «затворов», применяемых к подам до того, как `kube-scheduler` начнет их обрабатывать. Пока у пода в спецификации указан хотя бы один gate (в массиве `spec.schedulingGates`), планировщик просто игнорирует этот под.
- Под с установленными gates находится в фазе `Pending`, а в массиве `status.conditions` появляется условие `PodScheduled=False` с причиной `SchedulingGated`.
- **Зачем это нужно?** Исторически, если приложению нужно было дождаться какого-то внешнего события (например, готовности базы данных, выдачи квоты, одобрения администратора), разработчики использовали `initContainers`, которые в цикле пинговали внешний ресурс (busy-wait). Это создавало проблемы: под уже был запланирован на конкретную ноду (занимая там ресурсы), kubelet тратил CPU на цикл ожидания, IP-адрес уже был выделен. Scheduling gates решают эту проблему радикально: под «спит» на уровне API сервера и даже не доходит до этапа планирования на ноду.
- **Ограничения:** Добавить gate можно только в момент **создания** пода (обычно это делает MutatingAdmissionWebhook). Добавить gate к уже существующему поду нельзя. Снять gate можно только путем патчинга (удаления элемента из массива `schedulingGates`).

### 2.1 Gated под и снятие gate

Проверим, как это выглядит на практике.

```bash
# Применяем манифест пода с установленным gate
kubectl -n lab apply -f manifests/gates/pod.yaml

# Проверяем статус пода
kubectl -n lab get pod gated-demo
```

```text
NAME         READY   STATUS    RESTARTS   AGE
gated-demo   0/1     Pending   0          5s
```

Статус `Pending` сам по себе не говорит нам о причине. Это может быть нехватка ресурсов (CPU/Memory на нодах) или отсутствие подходящих taints/tolerations. Как отличить Gated-под от других причин?

```bash
# Изучаем условия статуса пода
kubectl -n lab get pod gated-demo -o jsonpath='Phase: {.status.phase}, Reason: {.status.conditions[?(@.type=="PodScheduled")].reason}{"\n"}'
# Вывод: Phase: Pending, Reason: SchedulingGated
```

В выводе `kubectl describe pod gated-demo` вы также увидите, что событий `FailedScheduling` от планировщика просто нет. Kube-scheduler игнорирует этот под.

Снимем gate, чтобы под мог запуститься. Делается это путем очистки массива `schedulingGates`:

```bash
# Патчим под, удаляя gate
kubectl -n lab patch pod gated-demo --type=merge -p '{"spec":{"schedulingGates":[]}}'
# Вывод: pod/gated-demo patched

# Проверяем снова
sleep 3
kubectl -n lab get pod gated-demo
```

```text
NAME         READY   STATUS    RESTARTS   AGE
gated-demo   1/1     Running   0          25s
```

Под моментально перешел в статус Running, так как kube-scheduler тут же взял его в работу.

### 2.2 Использование нескольких scheduling gates

Массив `schedulingGates` может содержать несколько затворов от разных контроллеров. Например:
```yaml
spec:
  schedulingGates:
  - name: "kueue.x-k8s.io/admission"
  - name: "security.company.com/scan-approved"
```
Под не будет запланирован, пока не будут сняты **оба** затвора. Разные операторы могут независимо снимать свои затворы, и только когда массив станет пустым, `kube-scheduler` вступит в игру.

### 2.3 Почему не initContainers? (Сравнение подходов)

| Характеристика | initContainers (busy-wait) | Scheduling Gates |
| :--- | :--- | :--- |
| **Захват ресурсов ноды** | Да (под уже зашедулен) | Нет (под висит в API сервере) |
| **Расход CPU/Сети** | Да (цикличные запросы) | Нет |
| **Выделение IP-адреса** | Да | Нет |
| **Влияние на Cluster Autoscaler**| Заставляет кластер скейлиться раньше времени | Не вызывает скейлинг нод |
| **Сложность настройки** | Просто (bash script) | Требует внешнего контроллера для снятия gate |

### 2.4 Интеграция с Kueue и пакетными нагрузками

Один из главных драйверов появления Scheduling Gates — проект **Kueue** (Job Queueing controller для Kubernetes). При запуске тысяч Machine Learning джобов одновременно, кластер может «лечь» от нехватки ресурсов, а поды зависнут в `Pending (FailedScheduling)`. Kueue перехватывает создание Job, вешает на поды `schedulingGate`, и держит их в очереди. По мере освобождения квот в кластере, Kueue поштучно снимает gates, обеспечивая плавную и управляемую загрузку GPU и CPU.

---

## Часть 3: In-place Pod resize — вертикальный скейл без рестарта (beta 1.33)

### Теория для изучения перед частью

- **In-place resize** (вертикальное масштабирование на лету) позволяет изменять параметры `requests` и `limits` для CPU и памяти у **уже запущенного и работающего пода**, не удаляя его. До появления этой фичи (которая стала beta в 1.33), любое изменение ресурсов в спецификации пода приводило к ошибке валидации, и под нужно было пересоздавать (что означало простой приложения).
- **Subresource `resize`:** Изменение ресурсов пода делается не обычным патчем спецификации (она по-прежнему иммутабельна для этих полей), а через специальный subresource API: `kubectl patch pod <name> --subresource resize -p '{...}'`.
- Можно изменять **только `cpu` и `memory`**. Ephemeral storage, GPU и другие ресурсы изменять нельзя.

### 3.1 Resize без рестарта (reality на нашем кластере)

Применим под с настроенным `resizePolicy` и базовыми ресурсами:

```bash
kubectl -n lab apply -f manifests/resize/pod.yaml
kubectl -n lab wait --for=condition=Ready pod/resize-demo --timeout=60s

# Смотрим базовые значения:
kubectl -n lab get pod resize-demo -o jsonpath='ДО: req={.spec.containers[0].resources.requests.cpu} lim={.spec.containers[0].resources.limits.cpu} restarts={.status.containerStatuses[0].restartCount} alloc={.status.containerStatuses[0].allocatedResources.cpu}{"\n"}'
```

```text
ДО: req=100m lim=200m restarts=0 alloc=100m
```

Обратите внимание на поле `allocatedResources`. Это то, что kubelet **реально** выделил на уровне cgroups на ноде. При старте оно совпадает с requests.

Сделаем **корректный resize**: мы поднимем и requests, и limits так, чтобы не нарушить правила.

```bash
kubectl -n lab patch pod resize-demo --subresource resize --type=strategic \
  -p '{"spec":{"containers":[{"name":"app","resources":{"requests":{"cpu":"150m"},"limits":{"cpu":"300m"}}}]}}'
# Вывод: pod/resize-demo patched

# Ждем пару секунд для применения kubelet'ом
sleep 3

kubectl -n lab get pod resize-demo -o jsonpath='ПОСЛЕ: req={.spec.containers[0].resources.requests.cpu} lim={.spec.containers[0].resources.limits.cpu} restarts={.status.containerStatuses[0].restartCount} alloc={.status.containerStatuses[0].allocatedResources.cpu}{"\n"}'
```

```text
ПОСЛЕ: req=150m lim=300m restarts=0 alloc=150m
```

Как видите, `allocatedResources.cpu` изменилось на `150m`, а счетчик `restarts` остался равен `0`. Контейнер получил больше процессорного времени на лету!

### 3.2 Механика работы resizePolicy: NotRequired vs RestartContainer

В спецификации `manifests/resize/pod.yaml` есть важный блок:

```yaml
resizePolicy:
- resourceName: cpu
  restartPolicy: NotRequired
- resourceName: memory
  restartPolicy: RestartContainer
```

**Почему так сделано?**
- **CPU (NotRequired):** Процессор — это сжимаемый ресурс (compressible). Если мы меняем лимиты CPU через cgroups, процесс внутри контейнера просто начинает получать больше или меньше тактов процессора (throttling). Приложению не нужно знать об этом, оно адаптируется автоматически.
- **Memory (RestartContainer):** Память — не сжимаемый ресурс. Многие рантаймы (например, Java JVM, Go Runtime, Node.js) читают лимиты памяти (`cgroups /sys/fs/cgroup/memory/...`) **только один раз при старте**. Если мы добавим памяти на лету, JVM этого не увидит и продолжит работать со старым heap-size, или даже упадет с OOMKilled, если мы урежем лимит, который она уже считает «своим». Поэтому для памяти безопаснее использовать `RestartContainer`, что заставит kubelet перезапустить контейнер с новыми лимитами, не пересоздавая сам объект Pod.

### 3.3 Поймать обе валидации (ограничения QoS и limit)

У In-place resize есть два жестких правила, нарушение которых отбивается API сервером.

**Правило 1: QoS-класс пода нельзя менять.**
Наш под принадлежит классу `Burstable` (т.к. requests < limits). Если мы попытаемся поднять `requests` до уровня `limits`, под должен бы стать `Guaranteed`. Но это запрещено!

```bash
# Попытка поднять requests.cpu до уровня limits (300m), что сделало бы класс Guaranteed:
kubectl -n lab patch pod resize-demo --subresource resize --type=strategic \
  -p '{"spec":{"containers":[{"name":"app","resources":{"requests":{"cpu":"300m"}}}]}}'
```

```text
The Pod "resize-demo" is invalid: spec: Forbidden: Pod QOS Class may not change as a result of resizing
```

**Правило 2: requests всегда должен быть ≤ limits.**

```bash
# Попытка сделать requests больше limits (500m > 300m):
kubectl -n lab patch pod resize-demo --subresource resize --type=json \
  -p '[{"op":"replace","path":"/spec/containers/0/resources/requests/cpu","value":"500m"}]'
```

```text
The Pod "resize-demo" is invalid: spec.containers[0].resources.requests: Invalid value: "500m": must be less than or equal to cpu limit of 300m
```

### 3.4 Как kubelet обновляет cgroups

Под капотом in-place resize работает следующим образом:
1. API сервер обновляет `spec.containers[].resources`.
2. Kubelet замечает изменение спецификации (через watch).
3. Kubelet проверяет, достаточно ли ресурсов на ноде (если мы увеличиваем requests). Если ресурсов нет, статус resize переходит в `Infeasible`.
4. Если ресурсы есть, kubelet обращается к Container Runtime (например, containerd через интерфейс CRI `UpdateContainerResources`).
5. Container Runtime обновляет лимиты непосредственно в файловой системе Linux cgroups (в `/sys/fs/cgroup/cpu.max` или `memory.max`).
6. Kubelet обновляет статус пода, устанавливая `allocatedResources` равным новым значениям.

### 3.5 Статус subresource resize и фазы применения

Вы можете отслеживать статус применения изменения через поле `status.resize`:
- `Proposed`: Запрос принят API сервером, ожидается реакция kubelet.
- `InProgress`: Kubelet принял запрос и применяет его (обновляет cgroups).
- `Deferred`: Kubelet не может применить изменения прямо сейчас (например, не хватает ресурсов на ноде), но попробует позже.
- `Infeasible`: Применение невозможно.

---

## Часть 4: Troubleshooting — боевые инциденты

### Теория: алгоритм диагностики по симптому

```text
Симптом
├─ Job висит `Active`, под `1/2 NotReady` ─► Логгер/сайдкар лежит в `containers[]`
│     Вместо этого используйте native sidecar: `initContainers` + `restartPolicy: Always`.
│
├─ Под завис в `Pending`, событий нет ─────► Проверьте `status.conditions`. Если `reason: SchedulingGated` —
│     на поде висит gate. Снимите его через `patch pod <name> --type=merge -p '{"spec":{"schedulingGates":[]}}'`.
│
├─ In-place resize отбит с ошибкой ────────► Читайте текст ошибки:
│     "QOS Class may not change"  -> Изменение `requests/limits` переводит под в другой QoS класс.
│                                    (Например: `Burstable` -> `Guaranteed`). Измените параметры так, чтобы класс сохранился.
│     "must be <= cpu limit"      -> Вы запрашиваете `requests` больше, чем установлен `limit`. Поднимите сначала `limit`.
│     "only cpu and memory mutable" -> Вы пытаетесь изменить `ephemeral-storage` или GPU. Это запрещено.
│
└─ Под OOMKilled после resize ─────────────► Вы понизили лимит памяти на лету (`NotRequired`), но приложение (напр. JVM) 
      не освободило память. Для памяти используйте `resizePolicy: RestartContainer`.
```

### Инцидент 1: Job не завершается (sidecar-антипаттерн)

Если вы видите, что пакетная обработка зависла, первым делом выполните:
```bash
kubectl get pods -l job-name=my-job
# NAME           READY   STATUS     RESTARTS
# my-job-abcde   1/2     NotReady   0
```
Если статус `1/2 NotReady`, а в `kubectl logs my-job-abcde -c <sidecar>` вы видите, что sidecar работает штатно — это 100% проблема отсутствия `restartPolicy: Always` в блоке `initContainers`. Перепишите манифест.

### Инцидент 2: Под завис в Pending из-за забытого Gate

Симптом: Под находится в фазе `Pending`, но `kubectl describe pod` не показывает никаких событий от планировщика (например, нет жалоб на нехватку CPU/Memory на нодах).
Диагностика:
```bash
kubectl get pod <pod-name> -o jsonpath='{.spec.schedulingGates}'
# Если вывод содержит объекты (например: [{"name":"kueue.x-k8s.io/admission"}]), 
# значит контроллер, который должен был снять gate, не отработал.
```
Решение: Разберитесь, почему внешний контроллер не снимает gate, или снимите его вручную (если это тестовая среда) с помощью команды патча.

### Инцидент 3: In-place resize отбит: нарушение QoS-класса

При попытке вертикального скейлинга вы получаете ошибку о QoS. Вспомните три класса QoS:
1. **Guaranteed**: У всех контейнеров пода проставлены `requests` == `limits` для CPU и Memory.
2. **Burstable**: По крайней мере у одного контейнера проставлены `requests` или `limits`, и при этом под не удовлетворяет условиям Guaranteed.
3. **BestEffort**: У пода вообще не проставлены `requests` и `limits`.

Вы не можете перевести под из Burstable в Guaranteed и наоборот. Чтобы поднять ресурсы Burstable-пода, вы должны убедиться, что `requests < limits` сохраняется хотя бы для одного ресурса.

### Бонус: общая диагностика Pod lifecycle

Используйте `kubectl get events --field-selector involvedObject.name=<pod-name>` для просмотра всех событий жизненного цикла пода. В свежих версиях Kubernetes (включая нашу 1.36) вы увидите события об успешном In-place resize: `Container <name> resized`.

---

## Проверка модуля

Запустите скрипт проверки, чтобы убедиться, что все практические задания выполнены корректно.

```bash
kubectl -n lab apply -f manifests/sidecar/job.yaml
kubectl -n lab apply -f manifests/gates/pod.yaml
kubectl -n lab apply -f manifests/resize/pod.yaml

bash verify/verify.sh
# Ожидаемый вывод:
# [OK] native sidecar: Job Complete, logshipper = init+restartPolicy:Always
# [OK] scheduling gate: gated-demo держится SchedulingGated до снятия gate
# [OK] in-place resize: resize-demo Ready, resizePolicy задан, allocatedResources.cpu=100m
# [OK] module 29 verified
```

---

## Финальная карта ресурсов модуля

| Название ресурса | Тип объекта | Демонстрируемая концепция |
|------------------|-------------|---------------------------|
| `sidecar-job` | Job | Native sidecar (initContainer + `restartPolicy: Always`). Корректное завершение Job. |
| `gated-demo` | Pod | Scheduling gate. Удержание пода в статусе Pending/SchedulingGated до ручного патча. |
| `resize-demo` | Pod | In-place Pod resize. Изменение CPU на лету, использование `resizePolicy`, разбор механизма cgroups и валидаций `requests<=limits` и QoS. |

---

## Теоретические вопросы (итоговые)

### Блок 1: Native sidecar
1. В чём принципиальное различие между обычным `initContainer` (без restartPolicy) и native sidecar (с `restartPolicy: Always`) с точки зрения блокировки запуска основных контейнеров?
2. Почему размещение sidecar-контейнера в массиве `containers[]` ломает логику работы ресурсов типа `Job`?
3. В каком порядке kubelet отправляет сигнал SIGTERM контейнерам при остановке пода с native sidecar? Почему выбран именно такой порядок?

### Блок 2: Scheduling gates
4. Каким образом механизм scheduling gates помогает экономить ресурсы нод и IP-адреса кластера по сравнению с традиционным подходом (busy-wait циклы в initContainers)?
5. Может ли kube-scheduler самостоятельно снять gate с пода, если на ноде появилось достаточно ресурсов? Почему?

### Блок 3: In-place resize
6. Через какой механизм (subresource) API сервера выполняется вертикальное масштабирование ресурсов на лету? Почему нельзя просто обновить поле `spec`?
7. Объясните причину, по которой для CPU рекомендуется устанавливать `resizePolicy: NotRequired`, а для Memory — `RestartContainer`. Как ведут себя популярные рантаймы (например, JVM) при изменении лимита памяти на лету?
8. Почему Kubernetes запрещает изменять QoS-класс пода в процессе in-place resize?

### Блок 4: Troubleshooting
9. Если под находится в фазе `Pending`, как отличить ситуацию нехватки ресурсов от применения Scheduling Gates?
10. Что означает статус resize `Infeasible` и в каком случае kubelet может установить его?

---


---

## Архитектурные нюансы и глубокое погружение (Deep Dive)

### 1. Почему Resize CPU работает без рестарта, а Memory часто требует рестарта?
Когда мы меняем `limits.cpu`, kubelet просто обновляет значение в `cpu.max` (для cgroups v2) или `cpu.cfs_quota_us` (для cgroups v1). Планировщик операционной системы (CFS - Completely Fair Scheduler) мгновенно начинает выдавать процессу больше или меньше микросекунд процессорного времени. Процесс (даже однопоточный) просто начинает выполняться быстрее или медленнее. Ему не нужно адаптироваться или перезапускаться.

С памятью ситуация принципиально иная. Если вы понижаете `limits.memory` ниже текущего потребления процесса (RSS), ядро Linux немедленно вызовет OOM Killer, и процесс будет убит с сигналом `SIGKILL` (Exit Code 137). Если вы повышаете лимит памяти, процесс может об этом никогда не узнать. Например, рантаймы со сборщиком мусора (Java, Go, .NET) вычисляют размер пула памяти (Heap) один раз при старте контейнера. 

Именно поэтому Kubernetes ввел `resizePolicy`. Оставив для `memory` политику `RestartContainer`, мы гарантируем, что приложение перезапустится и заново прочитает свои cgroups лимиты, выделив себе правильный размер Heap. Если ваше приложение написано на C/C++ или Rust и умеет динамически аллоцировать память через `malloc`, вы можете смело ставить `NotRequired` и для памяти!

### 2. Роль Container Runtime Interface (CRI) в In-place Resize
До версии Kubernetes 1.27 интерфейс CRI не поддерживал обновление ресурсов "на лету". Команда `UpdateContainerResources` была добавлена специально для фичи In-place Resize. Когда API сервер принимает ваш патч:
1. Kubelet замечает изменение спецификации.
2. Делает gRPC вызов `UpdateContainerResources` к containerd или CRI-O.
3. Container runtime напрямую изменяет параметры в `/sys/fs/cgroup/system.slice/...`.
Если CRI возвращает ошибку (например, диск переполнен или cgroup не отвечает), kubelet пометит статус `resize` как `Deferred` и попытается снова через некоторое время.

### 3. Взаимодействие Scheduling Gates и Cluster Autoscaler
Одной из главных проблем старого подхода с `initContainers` было ложное масштабирование кластера. 
Представьте ситуацию: 
- Под создается, но ему нужно дождаться подготовки внешней базы данных.
- Под использует `initContainer`, чтобы каждую секунду пинговать БД.
- Под переходит в состояние `Pending (FailedScheduling)`, если на нодах не хватает места для этого пода.
- Cluster Autoscaler видит `FailedScheduling` и заказывает новые виртуальные машины в облаке!
- Кластер расширяется, под запускается на новой ноде, но БД все еще не готова. Мы потратили деньги на новую ноду впустую, так как под просто ждет.

Scheduling Gates решают эту проблему: пока под имеет `reason: SchedulingGated`, Cluster Autoscaler **полностью игнорирует его** и не масштабирует кластер. Это колоссальная экономия денег в больших production средах, где используются инструменты вроде Kueue. Только когда внешний сервис (БД) готов, контроллер снимает gate, и только тогда Autoscaler может добавить ноду, если это действительно необходимо.

### 4. Native Sidecars и Service Mesh (Istio / Envoy)
В мире Service Mesh существует классическая проблема "гонки старта и остановки" (startup/shutdown race condition):
- **При старте:** Основное приложение пытается сделать исходящий сетевой запрос, но sidecar-прокси (Envoy) еще не успел загрузить конфигурацию. Запрос падает.
- **При остановке:** Envoy выключается быстрее, чем основное приложение завершает обработку текущего HTTP запроса. Приложение пытается отправить ответ в сеть, но Envoy уже мертв. Запрос падает.

Native Sidecars элегантно решают эту проблему:
- При запуске `kubelet` дожидается, когда `Envoy` (определенный как native sidecar) перейдет в статус `Started` и успешно пройдет свои `startupProbe`/`readinessProbe`. И только после этого `kubelet` запускает контейнер с основным приложением.
- При остановке пода (например, при выкатке новой версии Deployment), `kubelet` посылает `SIGTERM` основному приложению. `Envoy` продолжает работать и обслуживать исходящий трафик. Как только основное приложение корректно завершается, `kubelet` посылает `SIGTERM` контейнеру `Envoy`.

Это полностью устраняет необходимость в сложных хаках вроде скриптов `wait-for-it.sh` или переопределении `command` для задержки старта.

### 5. Лимиты на изменения ресурсов
Важно помнить, что In-place resize применяется только к CPU и Memory. Существуют ресурсы, которые невозможно изменить на лету:
- **Ephemeral Storage (`ephemeral-storage`)**: Локальный диск ноды. Вы не можете запросить больше дискового пространства без пересоздания пода, так как kubelet не может динамически перераспределять разделы `emptyDir`.
- **Devices / GPU (`nvidia.com/gpu`)**: Устройства пробрасываются в контейнер на этапе создания namespace с помощью Device Plugins. Добавить GPU "на лету" в уже запущенный контейнер невозможно архитектурно.
- **HugePages (`hugepages-2Mi`)**: Крупные страницы памяти выделяются заранее и их размер фиксирован.

### 6. Взаимодействие In-place Resize с Horizontal Pod Autoscaler (HPA) и Vertical Pod Autoscaler (VPA)
- **HPA**: Horizontal Pod Autoscaler основывает свои вычисления на значениях `requests` подов. Если вы измените `requests.cpu` пода через In-place resize, HPA автоматически пересчитает процент загрузки (Utilization). Это может привести к тому, что HPA уменьшит или увеличит количество реплик.
- **VPA**: Vertical Pod Autoscaler является главным выгодоприобретателем In-place resize. До версии 1.33 VPA работал исключительно в режиме "Recreate" — он убивал поды, чтобы применить новые ресурсы. Теперь VPA может использовать In-place resize, автоматически корректируя `requests` и `limits` подов на лету без их перезапуска! Это делает VPA безопасным для использования в Production для критичных stateful-нагрузок.


## Часто Задаваемые Вопросы (FAQ) и Продвинутые Сценарии

### Вопрос 1: Что произойдет, если OOM Killer убьет Native Sidecar?
Если `initContainer` (Native Sidecar) с `restartPolicy: Always` упадет или будет убит OOM Killer-ом:
1. Kubelet немедленно попытается его перезапустить, следуя логике Exponential Backoff (10s, 20s, 40s...).
2. Если в этот момент под находился в состоянии `Running` (основные контейнеры работают), то статус пода может временно смениться на `NotReady`, если у sidecar была настроена `readinessProbe` и она начала возвращать ошибки. 
3. Если `readinessProbe` не была настроена, то Kubernetes просто перезапустит sidecar в фоне. Основные контейнеры продолжат работу, однако они могут пострадать, если их логика зависела от sidecar (например, пропадет подключение к локальному Envoy).

### Вопрос 2: Как Native Sidecar влияет на расчет ресурсов пода (Requests/Limits)?
Расчет ресурсов для подов с Native Sidecars немного отличается от старых подов:
До Kubernetes 1.28 ресурсы пода (Requests) вычислялись как:
`MAX(Sum of Init Containers) + SUM(App Containers)`
С появлением Native Sidecars логика изменилась:
Native Sidecars работают параллельно с основными контейнерами, поэтому их ресурсы суммируются с основными контейнерами!
Новая формула:
`MAX(Sum of Regular Init Containers) + SUM(App Containers) + SUM(Native Sidecars)`
Таким образом, добавление Native Sidecar увеличит общее потребление ресурсов (Requests) пода, что повлияет на планирование и работу Cluster Autoscaler. Это логично, так как sidecar будет работать все время.

### Вопрос 3: Как работает In-place Resize с Pod Disruption Budgets (PDB)?
Pod Disruption Budgets управляют допустимым количеством "выселений" (evictions) подов. 
Поскольку In-place Resize не пересоздает под и не вызывает его eviction (при условии `resizePolicy: NotRequired` для CPU и отсутствия ошибок), PDB никак не блокирует и не замедляет процесс вертикального масштабирования. 
Даже если для памяти указан `RestartContainer`, kubelet перезапускает контейнер *внутри* пода, не удаляя сам под из кластера, поэтому PDB также не применяется. Это делает In-place Resize идеальным инструментом для обновления ресурсов в высокодоступных кластерах.

### Вопрос 4: Как Scheduling Gates защищают от "Thunder Herd" (Эффекта толпы)?
Представьте, что 1000 подов создаются одновременно. Если все они перейдут в `Pending` и планировщик начнет пытаться найти им место, это создаст колоссальную нагрузку на `kube-scheduler` и `etcd`. 
Если на эти поды повесить Scheduling Gates, они будут "спать" в API-сервере. Планировщик вообще не будет тратить процессорное время на оценку этих подов (вычисление Predicates/Priorities). Внешний контроллер (например, Kueue) может снимать затворы батчами по 50 подов. Планировщик спокойно обработает 50 подов, и только потом получит следующую порцию. Это радикально повышает стабильность Control Plane в больших кластерах.

### Вопрос 5: Можно ли использовать In-place resize для изменения Request до значений, превышающих Capacity ноды?
Нет. Когда вы отправляете патч `resize`, API сервер лишь валидирует синтаксис и правила QoS. 
Но затем `kubelet` на конкретной ноде, где уже крутится этот под, оценивает свободные ресурсы (Allocatable CPU/Memory). 
Если вы запросили `requests.cpu: 4000m`, а на ноде свободно только `2000m`, `kubelet` отклонит применение. 
Статус `status.resize` перейдет в `Deferred` или `Infeasible`, а реальные `allocatedResources` останутся прежними. 
Под **не будет** выселен (evicted) и не переедет на другую ноду! In-place resize работает только в рамках текущей ноды. Если вам нужно больше ресурсов, чем есть на ноде — вам придется удалить под вручную, чтобы планировщик перенес его на другую ноду.

### Вопрос 6: В каких случаях стоит избегать Native Sidecars?
Native Sidecars не подходят для:
1. Задач одноразовой инициализации (создание схемы БД, скачивание конфигов). Для этого используйте обычные `initContainers` (без restartPolicy).
2. Тяжелых вычислений, которые должны завершиться до старта приложения.
3. Совместимости со старыми версиями Kubernetes. Фича стала GA только в 1.33. Если у вас в парке есть кластеры 1.27 и ниже, манифесты с `restartPolicy: Always` внутри `initContainers` будут отвергнуты API-сервером или отработают некорректно.

---

## Архитектурные антипаттерны: Чего делать не следует

### 1. Подмена readinessProbe с помощью Scheduling Gates
Некоторые инженеры пытаются использовать Gates для ожидания готовности базы данных: ставят контроллер, который пингует БД и снимает Gate, когда БД оживает. 
**Почему это антипаттерн:** Gates блокируют *шедулинг* (выбор ноды). Если вы снимете Gate, под будет запланирован, но к тому времени БД может снова упасть. 
**Правильный путь:** Под должен быть запланирован, запущен, а его `readinessProbe` или `initContainer` (обычный) должен проверять БД. Gates созданы для квотирования и батчевого шедулинга, а не для синхронизации runtime-зависимостей!

### 2. Использование In-place resize как замены HPA
In-place resize не заменяет Horizontal Pod Autoscaler. Если ваше приложение (например, Nginx) получает скачок трафика, вертикальное масштабирование `limits.cpu` имеет физический предел (размер ноды). HPA с масштабированием по горизонтали всегда безопаснее и надежнее для stateless web-приложений. In-place resize (часто в связке с VPA) предназначен в первую очередь для **Stateful** нагрузок (БД, кеши, message brokers), где горизонтальное масштабирование сложно или невозможно без решардинга.

### 3. Native Sidecar для бизнес-логики
Если вы разбиваете монолит и помещаете часть бизнес-логики в Native Sidecar, вы совершаете ошибку. Native Sidecar предназначен исключительно для инфраструктурных задач (логи, метрики, прокси, секреты). Бизнес-логика должна жить в основных `containers[]`, чтобы ее завершение корректно отслеживалось контроллером Job, а ошибки приводили к рестартам всего пода или изменениям бизнес-статусов.

---

## Чему вы научились

В рамках этой лабораторной работы вы освоили три важнейших API-улучшения современных версий Kubernetes:
- **Native Sidecars:** Теперь вы знаете, как правильно интегрировать вспомогательные агенты (сборщики логов, прокси) в пакетные джобы без необходимости использовать костыли.
- **Scheduling Gates:** Вы поняли, как эффективно откладывать запуск подов на уровне control-plane, что является фундаментом для современных систем очередей (например, Kueue).
- **In-place Resize:** Вы научились изменять ресурсы работающим приложениям на лету, избегая даунтаймов и пересоздания подов, а также детально разобрались в механизме cgroups и ограничениях QoS.

---

## Эволюция жизненного цикла пода (History & Evolution)

### До Kubernetes 1.28: Эпоха костылей
До версии 1.28 разработчикам приходилось мириться с тем, что под — это монолитная сущность, которая не всегда подходит для сложных пакетных задач или инициализации. 
- Sidecars приходилось выключать через `kill` или специальные HTTP-хендлеры, что приводило к сложным оберткам (wrappers) в Docker-образах.
- Для отложенного старта приходилось использовать `initContainers`, которые в цикле `while true; do curl ...; sleep 5; done` ждали внешнего ресурса. Это расходовало ресурсы кластера и забивало логи.

### Kubernetes 1.28 - 1.29: Появление надежды
- **Native Sidecars (Alpha/Beta)**: Kubernetes начал поддерживать `restartPolicy: Always` в init-контейнерах. Это кардинально изменило правила игры для Service Mesh (Istio, Linkerd), позволив прокси-контейнерам запускаться до основного приложения и выключаться после него.
- **In-place Resize (Alpha)**: Появился концепт изменения ресурсов без перезапуска. Однако фича была нестабильной, и многие Container Runtimes (CRI) еще не поддерживали новую команду `UpdateContainerResources`.

### Kubernetes 1.30+: Зрелость (GA)
- **Scheduling Gates (GA в 1.30)**: Эта фича была стабилизирована, позволив создавать сложные системы оркестрации пакетных задач (Kueue). Планировщик больше не перегружается ожидающими подами.
- **In-place Resize (Beta в 1.33)**: Фича стала достаточно стабильной для включения по умолчанию в большинстве современных дистрибутивов Kubernetes. VPA (Vertical Pod Autoscaler) получил возможность работать в связке с In-place Resize, что сделало вертикальное масштабирование production-ready.
- **Native Sidecars (GA в 1.33)**: Полная стабилизация. Теперь это рекомендуемый паттерн для любых вспомогательных контейнеров.

---

## Взаимодействие фич между собой

Интересно наблюдать, как эти три фичи могут работать вместе в одном поде:

1. **Создание пода:** Вы отправляете манифест пода в API-сервер. В поде есть `Scheduling Gates`, `Native Sidecar` (например, сборщик метрик) и настроен `resizePolicy`.
2. **Ожидание:** Под мгновенно переходит в `Pending (SchedulingGated)`. Он не занимает ресурсов, не имеет IP-адреса и не нагружает `kube-scheduler`.
3. **Разблокировка:** Внешний контроллер (например, Kueue) снимает gate.
4. **Запуск Sidecar:** Планировщик назначает под на ноду. Kubelet скачивает образы и первым делом запускает Native Sidecar.
5. **Запуск Приложения:** Как только Sidecar переходит в `Started`, Kubelet запускает основные контейнеры.
6. **Масштабирование на лету:** Во время интенсивной работы основному приложению не хватает CPU. VPA замечает это и отправляет патч через subresource `resize`. Kubelet мгновенно обновляет cgroups (In-place resize), и приложение получает больше тактов процессора без рестарта.
7. **Завершение:** Приложение заканчивает работу и выходит с кодом 0. Kubelet видит это и посылает `SIGTERM` нашему Native Sidecar. Sidecar корректно завершается.
8. **Итог:** Job переходит в `Complete`. Мы получили идеальный конвейер выполнения!

---

## Резюме лучших практик (Best Practices)

1. **Всегда используйте `restartPolicy: Always` для sidecar-контейнеров.** Забудьте про старый подход с `containers[]`.
2. **Не используйте `initContainers` для ожидания внешних сервисов.** Переходите на `Scheduling Gates`, если у вас есть контроллер для их управления, или используйте логику retry внутри самого приложения.
3. **Настраивайте `resizePolicy: RestartContainer` для памяти.** Если ваше приложение использует сборку мусора (GC) или кеширует данные в памяти, динамическое изменение лимитов без перезапуска может привести к OOMKills.
4. **Сохраняйте QoS-классы.** При использовании In-place resize старайтесь не менять соотношение `requests` и `limits`, чтобы не нарушить гарантии QoS (Quality of Service).
5. **Следите за метриками.** Используйте Prometheus и kube-state-metrics для отслеживания состояний `SchedulingGated` и `Infeasible` resize-патчей.

---

## Уборка

После успешного завершения всех заданий, очистите namespace с помощью подготовленного скрипта:

```bash
bash verify/cleanup.sh
```

> **Следующие шаги:** В соответствии с архитектурным дизайном новых модулей (см. handoff `NEW-MODULES-DESIGN.md`), вы можете перейти к модулю **NM-3 (DRA — Dynamic Resource Allocation)** для изучения работы с GPU и ускорителями в AI-нагрузках, или к модулю **NM-4 (Kueue/JobSet)**, где концепции scheduling gates и native sidecars объединяются для управления сложными очередями пакетных задач в масштабах кластера.

---

## Практические задания (отработка)

Для закрепления материала, выполните практические задания, расположенные в директории `tasks/`:
1. **`tasks/01-native-sidecar.md`** — Сравните поведение native sidecar в Job с антипаттерном. Напишите свой манифест с нуля.
2. **`tasks/02-scheduling-gates.md`** — Создайте под с gate, проанализируйте его статусы через `kubectl get pod -o yaml` и снимите gate с помощью JSON-патча.
3. **`tasks/03-inplace-resize.md`** — Выполните in-place resize для CPU без рестарта, а затем попытайтесь нарушить валидации (QoS и limits).

**Задания повышенной сложности (дополнительно):**
4. Выполните resize **ПАМЯТИ** (`requests.memory`) для пода `resize-demo`. Проверьте значение `restartCount` до и после операции, чтобы убедиться, что настройка `resizePolicy: RestartContainer` сработала корректно и контейнер был перезапущен.
5. Создайте под сразу с **ДВУМЯ** scheduling gates (например, `gate-a` и `gate-b`). Снимайте их по одному и убедитесь, что под переходит в `Running` только после удаления последнего затвора.

---

## Шпаргалка

Сохраните эти команды для повседневной работы:

```bash
# === Native sidecar ===
# Конфигурация: поместите контейнер в initContainers и добавьте restartPolicy: Always.
# Проверка наличия native sidecar в Job:
kubectl -n lab get job <job-name> -o jsonpath='{.spec.template.spec.initContainers[*].restartPolicy}'

# === Scheduling gates ===
# Проверка причины зависания в Pending:
kubectl -n lab get pod <pod-name> -o jsonpath='{.status.conditions[?(@.type=="PodScheduled")].reason}' 
# Ожидаемый вывод: SchedulingGated

# Снятие ВСЕХ gates (патч пустым массивом):
kubectl -n lab patch pod <pod-name> --type=merge -p '{"spec":{"schedulingGates":[]}}'

# === In-place resize ===
# Патч ресурсов (CPU и/или Memory) через специальный subresource "resize":
kubectl -n lab patch pod <pod-name> --subresource resize --type=strategic \
  -p '{"spec":{"containers":[{"name":"<container-name>","resources":{"requests":{"cpu":"150m"},"limits":{"cpu":"300m"}}}]}}'

# Проверка реально выделенных ресурсов (allocatedResources) и статуса изменения:
kubectl -n lab get pod <pod-name> -o jsonpath='Allocated: {.status.containerStatuses[0].allocatedResources.cpu}, Status: {.status.resize}{"\n"}'

# === Быстрая очистка лабораторного окружения ===
kubectl -n lab delete job,pod --all
```
