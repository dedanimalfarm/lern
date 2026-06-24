# Лабораторная работа 19: CRD и операторы (расширение Kubernetes API)

## Оглавление
<!-- TOC -->
- [Предварительные требования](#предварительные-требования)
- [Стартовая проверка](#стартовая-проверка)
- [Введение: Kubernetes как Платформа](#введение-kubernetes-как-платформа)
- [Часть 1: CustomResourceDefinition (CRD)](#часть-1-customresourcedefinition-crd)
  - [Теория: Архитектура расширения API](#теория-архитектура-расширения-api)
  - [1.1 Анатомия манифеста CRD](#11-анатомия-манифеста-crd)
  - [1.2 Регистрация CRD в кластере](#12-регистрация-crd-в-кластере)
- [Часть 2: Custom Resources (CR) и Схема](#часть-2-custom-resources-cr-и-схема)
  - [Теория: OpenAPI Schema, Pruning и CEL](#теория-openapi-schema-pruning-и-cel)
  - [2.1 Создание CR и проверка валидации](#21-создание-cr-и-проверка-валидации)
  - [2.2 Демонстрация Server-side pruning](#22-демонстрация-server-side-pruning)
- [Часть 3: Operator Pattern (Паттерн Оператор)](#часть-3-operator-pattern-паттерн-оператор)
  - [Теория: Reconcile Loop, Informers и Идемпотентность](#теория-reconcile-loop-informers-и-идемпотентность)
  - [Теория: Finalizers и OwnerReferences](#теория-finalizers-и-ownerreferences)
  - [3.1 Наблюдение за существующим оператором (prometheus-operator)](#31-наблюдение-за-существующим-оператором-prometheus-operator)
  - [3.2 Запуск собственного контроллера (на примере Kopf)](#32-запуск-собственного-контроллера-на-примере-kopf)
- [Часть 4: Интеграция с kubectl и API-сервером](#часть-4-интеграция-с-kubectl-и-api-сервером)
  - [Теория: Subresources и Printer Columns](#теория-subresources-и-printer-columns)
  - [4.1 Практика масштабирования через subresources.scale](#41-практика-масштабирования-через-subresourcesscale)
- [Часть 5: Troubleshooting (Диагностика инцидентов)](#часть-5-troubleshooting-диагностика-инцидентов)
  - [Методология диагностики CRD/CR](#методология-диагностики-crdcr)
  - [Инцидент 1: CR отклонён валидатором (Invalid value / Required)](#инцидент-1-cr-отклонён-валидатором-invalid-value--required)
  - [Инцидент 2: Объект завис в статусе Terminating (Проблема с Finalizer)](#инцидент-2-объект-завис-в-статусе-terminating-проблема-с-finalizer)
  - [Инцидент 3: `kubectl get <kind>` — «not found» / «the server doesn't have a resource type»](#инцидент-3-kubectl-get-kind--not-found--the-server-doesnt-have-a-resource-type)
  - [Инцидент 4: Контроллер работает нестабильно (Отсутствие Leader Election / RBAC ошибки)](#инцидент-4-контроллер-работает-нестабильно-отсутствие-leader-election--rbac-ошибки)
- [Проверка модуля](#проверка-модуля)
- [Финальная карта ресурсов модуля](#финальная-карта-ресурсов-модуля)
- [Теоретические вопросы (итоговые)](#теоретические-вопросы-итоговые)
- [Практические задания (отработка)](#практические-задания-отработка)
- [Шпаргалка](#шпаргалка)
- [Чему вы научились](#чему-вы-научились)
- [Уборка](#уборка)
- [Решения (Solutions)](#решения-solutions)
<!-- /TOC -->

> ⏱ время ~45-60 мин · сложность 4.5/5 · пререквизиты: Трек 1, Трек 3 (RBAC, API)

**Цель:** глубоко погрузиться в механизмы, которые превращают Kubernetes из обычного «оркестратора контейнеров» в мощную, расширяемую платформу. Вы изучите CustomResourceDefinition (создание своих типов данных), валидацию схем на базе OpenAPI и CEL, а также архитектуру операторов (CRD + контроллер) на реальных и учебных примерах.

---

## Предварительные требования

```bash
# kubeconfig нашего кластера (Kubespray); на другом стенде — свой путь/контекст
export KUBECONFIG=/root/.kube/kubespray.conf

# Создадим namespace для лабораторной
kubectl get ns lab >/dev/null 2>&1 || kubectl create ns lab

# Проверим версию кластера
kubectl version -o json 2>/dev/null | grep -i gitVersion | head -1
```

## Стартовая проверка

Убедитесь, что кластер доступен и ноды находятся в статусе Ready:
```bash
kubectl get nodes
```

---

## Введение: Kubernetes как Платформа

Исторически Kubernetes создавался для управления подами, сервисами и томами. Однако со временем стало ясно, что его декларативный API, идемпотентность и механизм `watch` (подписка на изменения) образуют идеальную базу для управления *любыми* ресурсами: от баз данных в кластере до облачных виртуальных машин (например, через Crossplane) или CI/CD пайплайнов (ArgoCD, Tekton).

**Почему не использовать ConfigMap для хранения конфигурации своих приложений?**
* **Отсутствие схемы:** В ConfigMap можно записать любую строку, опечатка не вызовет ошибку на этапе `kubectl apply`.
* **Нет статус-поля:** ConfigMap не может хранить раздельно желаемое состояние (`spec`) и фактическое (`status`).
* **Нет контроля доступа на уровне типа:** Нельзя дать права "только на создание баз данных", RBAC применяется ко всем ConfigMap в неймспейсе сразу.
* **Нет интеграции с kubectl:** Для ConfigMap нельзя настроить удобные столбцы `kubectl get` или использовать команду `kubectl scale`.

**Custom Resource (CR)** решает все эти проблемы, делая ваш объект полноправным гражданином Kubernetes API.

---

## Часть 1: CustomResourceDefinition (CRD)

### Теория: Архитектура расширения API

Чтобы API-сервер Kubernetes начал понимать новый тип объектов (Custom Resource), его нужно зарегистрировать. Это делается с помощью объекта `CustomResourceDefinition`.

```text
       [ Пользователь / CI-CD ]
                  │
          (kubectl apply)
                  │
                  ▼
    +---------------------------+
    |  Kubernetes API Server    |
    |                           |
    |  [Встроенные ресурсы]     |
    |   - Pod, Deployment...    |
    |                           |
    |  [Пользовательские API]   |
    |   - WebApp (наш CRD)      | <--- Мы регистрируем этот тип!
    |   - Prometheus (внешний)  |
    +---------------------------+
         │                 │
    Сохранение в etcd   Отправка событий (watch)
         │                 │
         ▼                 ▼
     [ etcd ]         [ Контроллеры / Операторы ]
```

Идентификация любого ресурса в Kubernetes состоит из трёх элементов (GVK):
* **Group:** Группа API (например, `lab.example.com`). Позволяет избежать конфликтов имен (ваш `WebApp` не пересечётся с `WebApp` от другой компании).
* **Version:** Версия (например, `v1`). Отражает стадию зрелости API (`v1alpha1` -> `v1beta1` -> `v1`).
* **Kind:** Имя типа (например, `WebApp`).

**Версионирование CRD и `spec.versions[]`**
Ресурсы могут эволюционировать. В CRD можно описать несколько версий.

| Поле версии | Что означает |
|-------------|--------------|
| `served: true` | Данная версия доступна через REST API (можно делать GET/POST по этому `apiVersion`). |
| `storage: true` | Указывает, в каком формате ресурс **физически хранится** в etcd. Ровно ОДНА версия из всех должна иметь `storage: true`. |
| `deprecated: true` | Версия устарела. API-сервер отдаст Warning клиенту (например, kubectl напечатает желтый текст). |

> **Webhook Conversion:** Если клиент запрашивает ресурс в версии `v1beta1`, а в etcd он хранится как `v1`, API-сервер автоматически конвертирует его на лету. Если поля кардинально изменились (например, поле переименовано), применяется механизм `spec.conversion.strategy: Webhook`, который вызывает внешний сервис для трансляции данных между версиями.

### 1.1 Анатомия манифеста CRD

Изучим структуру нашего CRD (файл `manifests/crd.yaml`):

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: webapps.lab.example.com     # Должно быть в формате: <plural>.<group>
spec:
  group: lab.example.com
  names:
    kind: WebApp
    plural: webapps
    singular: webapp
    shortNames:
      - wa                          # Позволяет писать: kubectl get wa
    categories:
      - all                         # Позволяет попадать в 'kubectl get all'
  scope: Namespaced                 # Объект будет жить в конкретном namespace (как Pod)
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        # Здесь описывается OpenAPI валидация (см. Часть 2)
        openAPIV3Schema:
          type: object
```

### 1.2 Регистрация CRD в кластере

**Цель:** зарегистрировать новый тип `WebApp` в кластере.

```bash
# Применяем CRD
kubectl apply -f manifests/crd.yaml

# Убеждаемся, что CRD зарегистрирован
kubectl get crd webapps.lab.example.com

# Проверяем видимость нового ресурса в API-сервере
kubectl api-resources | grep -i webapp
# Вывод: webapps   wa   lab.example.com/v1   true   WebApp
```

**Контрольные вопросы:**
1. Что происходит в API-сервере при создании объекта `CustomResourceDefinition`?
2. Почему для имени CRD обязательно использовать нотацию `<plural>.<group>`?
3. В чём отличие `served: true` от `storage: true` для версии API?

---

## Часть 2: Custom Resources (CR) и Схема

### Теория: OpenAPI Schema, Pruning и CEL

Экземпляр CRD называется **Custom Resource (CR)**. Когда вы делаете `kubectl apply` для CR, API-сервер проводит строгую проверку структуры (валидацию) перед тем как сохранить объект в базу `etcd`.

Эта проверка настраивается в CRD через `openAPIV3Schema`.

#### 1. Структурная схема (Server-side pruning)
С Kubernetes 1.16+ схемы стали "структурными". Это значит, что API-сервер реализует **pruning (обрезку)**.
Если вы в манифесте укажете поле, которого **нет** в `openAPIV3Schema` (например, опечатка `replcas: 3` вместо `replicas`), API-сервер молча **вырежет** это неизвестное поле перед сохранением в etcd. 
Это защищает контроллеры от мусора. Чтобы разрешить произвольные JSON-структуры в определённом поле (например, для передачи сырых конфигураций), используется флаг `x-kubernetes-preserve-unknown-fields: true`.

#### 2. Базовая валидация типов (OpenAPI)
Можно задавать типы (`string`, `integer`, `boolean`, `array`), обязательность полей (`required`), лимиты (`minimum`, `maximum`, `maxLength`), регулярные выражения (`pattern`).

```yaml
        properties:
          image:
            type: string
          replicas:
            type: integer
            minimum: 1
            maximum: 10
```

#### 3. Продвинутая валидация (CEL - Common Expression Language)
До Kubernetes 1.29 для сложной логики (например: "поле B обязательно, если поле A = true", или "minReplicas должно быть меньше maxReplicas") требовалось поднимать отдельный микросервис — Validating Admission Webhook. 
Теперь можно писать правила прямо в CRD с помощью `x-kubernetes-validations` (CEL):

```yaml
    x-kubernetes-validations:
    - rule: "self.spec.replicas % 2 == 0"
      message: "Количество реплик должно быть четным"
    - rule: "self.metadata.name.startsWith('prod-') ? self.spec.replicas >= 3 : true"
      message: "Prod-окружения должны иметь минимум 3 реплики"
```
*Преимущество CEL:* Правила выполняются мгновенно прямо внутри API-сервера, не требуя сетевых запросов к вебхукам (отсутствие точек отказа, задержек и проблем с сертификатами).

```text
    [ Жизненный цикл запроса kubectl apply -f my-webapp.yaml ]

Authentication -> Authorization (RBAC)
      │
      ▼
Mutating Admission Webhooks (изменяют манифест на лету, если настроено)
      │
      ▼
Object Schema Validation (OpenAPI: типы, required, min/max, pruning)
      │
      ▼
Validating Admission (в т.ч. выполнение правил CEL внутри схемы)
      │
      ▼
Сохранение в etcd (Успех!)
```

### 2.1 Создание CR и проверка валидации

Попробуем создать валидный объект:
```bash
# Изучите манифест (содержит spec.image и spec.replicas)
cat manifests/webapp.yaml

# Применим его
kubectl apply -f manifests/webapp.yaml

# Проверим, что ресурс создался
kubectl -n lab get webapp
```

Теперь проверим, как работает `openAPIV3Schema`. Попробуем создать невалидные объекты:
```bash
# 1. Попытка задать > 10 реплик (сработает правило maximum)
kubectl -n lab apply -f broken/scenario-01/bad-webapp.yaml
# Ожидаемый ответ: The WebApp "bad-webapp" is invalid: spec.replicas: Invalid value: 99: spec.replicas: Invalid value: 99: must be less than or equal to 10

# 2. Попытка не указать image (сработает правило required)
cat <<EOF | kubectl apply -f -
apiVersion: lab.example.com/v1
kind: WebApp
metadata:
  name: missing-image
  namespace: lab
spec:
  replicas: 2
EOF
# Ожидаемый ответ: The WebApp "missing-image" is invalid: spec.image: Required value
```

### 2.2 Демонстрация Server-side pruning

Создадим ресурс с полем `unsupportedField`, которого нет в схеме CRD:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: lab.example.com/v1
kind: WebApp
metadata:
  name: pruned-webapp
  namespace: lab
spec:
  image: nginx:latest
  replicas: 1
  unsupportedField: "this will be dropped silently"
EOF

# Проверим YAML в кластере
kubectl -n lab get webapp pruned-webapp -o yaml | grep unsupportedField
# Ничего не выведет! API-сервер вырезал это поле.
```

**Контрольные вопросы:**
1. Что такое Server-side pruning и для чего он нужен?
2. Какие преимущества у CEL-валидации перед Validating Webhooks?
3. На каком этапе API-запроса происходит проверка OpenAPI-схемы?

---

## Часть 3: Operator Pattern (Паттерн Оператор)

### Теория: Reconcile Loop, Informers и Идемпотентность

Сам по себе CRD и CR — это просто записи в базе данных etcd. Создав `WebApp`, вы не запустили ни одного контейнера. Чтобы CR превратился в реальные поды, нужна активная логика — **Контроллер (или Оператор)**.

Оператор непрерывно отслеживает состояние объектов (через механизм `watch`) и выполняет цикл согласования — **Reconcile Loop**.

```text
+---------------------------------------------------+
|                  Kubernetes Cluster               |
|                                                   |
|  [ CR "WebApp" ] <--- watch ---+                  |
|       ^                        |                  |
|       | update status          |                  |
|       v                        v                  |
|  +---------------------------------------------+  |
|  |                Оператор                     |  |
|  |  +-------------------+   +---------------+  |  |
|  |  | Informer / Cache  |-->|  Workqueue    |  |  |
|  |  +-------------------+   +---------------+  |  |
|  |                                |            |  |
|  |                                v            |  |
|  |                      +-------------------+  |  |
|  |                      | Reconcile(ns/name)|  |  |
|  |                      +-------------------+  |  |
|  +--------------------------------|------------+  |
|                                   |               |
|  [ Deployment ] <--- create/update/delete         |
|  [ Service    ] <--- create/update/delete         |
+---------------------------------------------------+
```

**Шаги Reconcile:**
1. **Observe (Наблюдение):** Получение текущего желаемого состояния из CR (например, 3 реплики). Получение фактического состояния кластера (сколько Deployment реально запущено).
2. **Diff (Сравнение):** Сравнение желаемого и действительного.
3. **Act (Действие):** Принятие мер: создание Deployment, масштабирование или изменение образа.
4. **Update Status:** Запись текущего фактического состояния в поле `status` кастомного ресурса.

**Важнейшие свойства операторов:**
* **Идемпотентность:** Функция `Reconcile()` должна безопасно вызываться много раз подряд с одним и тем же входом, не создавая дубликатов ресурсов.
* **Level-triggered (срабатывание по уровню):** Контроллер не полагается на последовательность *событий* ("было 1, стало 2"), так как события могут потеряться. Он смотрит на *конечное состояние* в базе ("сейчас должно быть 2") и приводит систему к этому уровню.

### Теория: Finalizers и OwnerReferences

**OwnerReferences (Владение)**
Когда оператор создает Deployment на основе `WebApp`, он добавляет в `metadata.ownerReferences` Деплоймента ссылку на `WebApp`.
*Зачем?* Если вы удалите `WebApp`, встроенный Garbage Collector Kubernetes увидит связь и **каскадно удалит** зависящие от него Deployment и Service. Без этого пришлось бы чистить хвосты вручную или усложнять логику контроллера.

**Finalizers (Финализаторы)**
Что если оператор создает ресурсы *вне* Kubernetes (например, поднимает AWS S3 бакет или записи в Cloudflare)? GC Kubernetes не может дотянуться до облака.
Для этого используются Finalizers. В метаданные `WebApp` прописывается строчка (например `webapp.operator.io/cleanup`). 
* Механизм: При попытке выполнить `kubectl delete`, API-сервер *не удаляет* объект из БД. Он ставит ему метку времени `metadata.deletionTimestamp`.
* Объект зависает в статусе `Terminating`.
* Оператор видит это событие, идёт в AWS, удаляет S3 бакет.
* Когда внешняя уборка окончена, оператор удаляет свою строку из массива `finalizers`.
* Когда массив финализаторов становится пустым, Kubernetes окончательно стирает объект из etcd.

---

### 3.1 Наблюдение за существующим оператором (prometheus-operator)

Вы уже встречали операторы в других модулях:
```bash
# CRD, которыми управляет prometheus-operator:
kubectl get crd | grep monitoring.coreos.com
# Вывод: alertmanagers, prometheuses, servicemonitors, prometheusrules...

# Сам под контроллера-оператора:
kubectl -n monitoring get pods | grep operator
# Вывод: kube-prometheus-stack-operator-...   Running

# Вспомните: когда вы создаете ServiceMonitor, оператор видит его, 
# генерирует конфигурацию scrape_configs и перезагружает сервер Prometheus.
```

### 3.2 Запуск собственного контроллера (на примере Kopf)

CRD `WebApp` сейчас безжизненна. Запустим контроллер, написанный на Python с использованием фреймворка Kopf (`controller/operator.py`). Он слушает события `WebApp` и управляет соответствующими `Deployment` и `Service`.

```bash
# 1. Установим зависимости для Python
pip install -r controller/requirements.txt

# 2. Запустим контроллер локально на вашей машине (он будет общаться с кластером через ~/.kube/config)
# Запускаем в фоновом режиме (подавляя вывод, чтобы не мешал в терминале)
kopf run controller/operator.py -A > /tmp/operator.log 2>&1 &
OPERATOR_PID=$!
echo "Operator started with PID: $OPERATOR_PID"

# Проверим логи (он уже должен был поймать ранее созданные webapp и создать им Deployment)
sleep 3
cat /tmp/operator.log
```

Теперь посмотрим магию в действии:

```bash
# 3. Создадим новый CR — контроллер сам развернёт Deployment+Service
cat <<EOF | kubectl apply -f -
apiVersion: lab.example.com/v1
kind: WebApp
metadata: 
  name: test-webapp
  namespace: lab
spec: 
  replicas: 2
  image: nginx:alpine
EOF

# Ждем пару секунд и проверяем созданные дочерние ресурсы:
kubectl -n lab get deploy test-webapp-deploy
kubectl -n lab get svc test-webapp-svc
# Они появились сами!

# Проверим, что контроллер записал статус:
kubectl -n lab get webapp test-webapp -o yaml | grep -A2 status:
# Должно быть: status.availableReplicas: 2

# 4. Проверим идемпотентность и Level-triggered логику:
# Изменим количество реплик на 3
kubectl -n lab patch webapp test-webapp --type=merge -p '{"spec":{"replicas":3}}'

# Контроллер моментально масштабирует Deployment:
kubectl -n lab get deploy test-webapp-deploy -w
# Нажмите Ctrl+C, когда увидите 3/3 реплик

# 5. Каскадное удаление (Garbage Collection по ownerReferences):
kubectl -n lab delete webapp test-webapp

# Проверим, что дочерние ресурсы удалились:
kubectl -n lab get deploy,svc -l app=test-webapp
# Вывод должен быть пуст
```

*После теста не забудьте остановить локальный процесс оператора:*
```bash
kill $OPERATOR_PID
```

> **Прод-реализация:** В реальной жизни операторы пишут на Go (с использованием Kubebuilder / Operator SDK) и разворачивают как Pod'ы внутри кластера с собственным `ServiceAccount` и строгим RBAC (чтобы контроллер WebApp не мог случайно удалить чужие секреты).

**Контрольные вопросы:**
1. Объясните принцип "Level-triggered" логики. Чем она лучше "Edge-triggered" (срабатывания по событиям)?
2. Что произойдет, если мы удалим `WebApp`, у которого есть Finalizer, но сам контроллер в этот момент "упал" (CrashLoopBackOff)?
3. В чём отличие `ownerReferences` от `finalizers`?

---

## Часть 4: Интеграция с kubectl и API-сервером

### Теория: Subresources и Printer Columns

В CRD можно настроить отображение ресурса в консоли, сделав его поведение неотличимым от родных ресурсов Kubernetes.

* **`additionalPrinterColumns`:** Позволяет вывести значения из JSON-полей объекта прямо в `kubectl get`. Например, достать версию образа из `.spec.image`.
* **`subresources.status`:** Создаёт отдельный endpoint `/apis/lab.example.com/v1/namespaces/lab/webapps/my-webapp/status`. Это крайне важно с точки зрения безопасности! Пользователям (через RBAC) можно дать права на редактирование основного ресурса, а права на обновление статуса дать *только* СервисАккаунту контроллера. Так пользователи не смогут подделать статус.
* **`subresources.scale`:** Позволяет стандартным командам (вроде `kubectl scale` или HorizontalPodAutoscaler) работать с вашим кастомным ресурсом, указывая, где в JSON лежит целевое количество реплик и фактическое.

### 4.1 Практика масштабирования через subresources.scale

Наш CRD уже настроен с `subresources.scale`:
```yaml
      subresources:
        status: {}
        scale:
          specReplicasPath: .spec.replicas
          statusReplicasPath: .status.availableReplicas
```

Давайте протестируем:
```bash
# Возьмем существующий (или создадим новый) webapp
kubectl -n lab apply -f manifests/webapp.yaml

# Проверим вывод столбцов (работает additionalPrinterColumns)
kubectl -n lab get wa -o wide
# NAME        IMAGE              REPLICAS   AGE
# my-webapp   nginx:1.27-alpine  3          ...

# Масштабируем через стандартный инструмент:
kubectl -n lab scale webapp my-webapp --replicas=5
# Output: webapp.lab.example.com/my-webapp scaled

# Проверим:
kubectl -n lab get wa my-webapp
# Replicas должно стать 5
```

---

## Часть 5: Troubleshooting (Диагностика инцидентов)

### Методология диагностики CRD/CR

При работе с CRD/Операторами проблемы делятся на три слоя абстракции:

```text
Где проблема?
  ├─ 1. CR не СОЗДАЁТСЯ (kubectl apply падает)
  │     ├─ Ошибка "Invalid value" / "Required value"  -> Проблема в СХЕМЕ (openAPIV3Schema/CEL).
  │     └─ Ошибка "no matches for kind WebApp"        -> CRD не применён или неверная group/version.
  │
  ├─ 2. CR создан, но НИЧЕГО НЕ ПРОИСХОДИТ (дочерние ресурсы не появляются)
  │     ├─ Контроллер не запущен.
  │     ├─ Ошибки RBAC у контроллера (нет прав создать Deployment). -> Читать логи пода оператора.
  │     └─ Ошибка в логике оператора (паника в коде).
  │
  └─ 3. CR не УДАЛЯЕТСЯ (завис в Terminating)
        └─ Не снят finalizer (оператор мертв или внешняя система API недоступна).
```

### Инцидент 1: CR отклонён валидатором (Invalid value / Required)

**Симптом:** При применении манифеста вы получаете длинный текст ошибки от API-сервера.
**Причина:** Несоответствие ресурса `openAPIV3Schema` в CRD.
**Решение:** 
1. Внимательно прочитайте ошибку. API-сервер всегда указывает конкретный путь, например `spec.replicas`.
2. Проверьте манифест CRD (команда `kubectl get crd webapps.lab.example.com -o yaml`), найдите это поле и посмотрите ограничения (`minimum`, `required`).
3. Исправьте свой `webapp.yaml`.

### Инцидент 2: Объект завис в статусе Terminating (Проблема с Finalizer)

**Симптом:** Вы удаляете ресурс `kubectl delete webapp stuck-webapp`, команда "зависла" и не возвращает управление. Вы нажимаете Ctrl+C. Ресурс остаётся в кластере со статусом `Terminating`.
**Причина:** В объекте прописан `metadata.finalizers`, но контроллер, который должен его обработать и удалить, не работает.
**Решение:**
1. Посмотреть финализаторы объекта: 
   `kubectl -n lab get webapp my-webapp -o jsonpath='{.metadata.finalizers}'`
2. Найти и починить контроллер, чтобы он штатно выполнил очистку.
3. *Крайняя мера (только если внешняя система очищена вручную):* Принудительно удалить финализатор патчем:
   ```bash
   kubectl -n lab patch webapp my-webapp --type=merge -p '{"metadata":{"finalizers":[]}}'
   ```
   Как только массив опустеет, объект исчезнет.

### Инцидент 3: `kubectl get <kind>` — «not found» / «the server doesn't have a resource type»

**Симптом:** Вы печатаете команду, но получаете ошибку о неизвестном ресурсе.
**Причины:**
1. Опечатка в `kind` (например, `webap`). Пользуйтесь `shortNames` (например, `wa`), они редко меняются.
2. CRD физически не применен в кластере: проверьте `kubectl get crd | grep example.com`.
3. В `apiVersion` манифеста указана неверная группа или версия (например `apiVersion: example.com/v2` вместо `lab.example.com/v1`).

### Инцидент 4: Контроллер работает нестабильно (Отсутствие Leader Election / RBAC ошибки)

**Симптом:** Состояние дочерних ресурсов (например, Deployment) постоянно "прыгает" туда-сюда. В событиях (`kubectl get events`) видны частые Create/Delete/Update.
**Причина (Split-brain):** В кластере запущено несколько реплик контроллера без механизма **Leader Election** (выбор лидера). Оба процесса реагируют на одни и те же CR и мешают друг другу.
**Причина (RBAC):** Если контроллер вообще ничего не делает, часто проблема в том, что его `ServiceAccount` не имеет прав (ClusterRole) на управление целевыми ресурсами (Deployment, Service). Проверяйте логи: `kubectl logs <operator-pod>` на предмет "Forbidden".

---

## Проверка модуля

```bash
# Применим базовые манифесты, если не применили ранее
kubectl apply -f manifests/crd.yaml
kubectl apply -f manifests/webapp.yaml

# Запуск автопроверки
bash verify/verify.sh
# Вывод:
# [OK] CRD WebApp registered
# [OK] my-webapp instance exists
# [OK] module 19 verified
```

---

## Финальная карта ресурсов модуля

| Ресурс | Роль и назначение |
|--------|-------------------|
| `webapps.lab.example.com` (CRD) | Расширение API своим типом, объявление схемы, правил OpenAPI и CEL. |
| `my-webapp` (CR) | Экземпляр нашего ресурса. Демонстрация валидации, printer columns и subresources. |
| `bad-webapp` (broken) | Демонстрация отклонения ресурса по схеме Admission-контроллером. |
| `prometheus-operator` | Пример реального production-grade оператора. |
| `operator.py` (Kopf) | Учебный контроллер для понимания Reconcile Loop. |

---

## Теоретические вопросы (итоговые)

1. Почему Kubernetes использует декларативную модель и Level-triggered подход в контроллерах вместо Edge-triggered (на основе событий)?
2. На каком этапе HTTP-запроса API-сервер применяет правила `x-kubernetes-validations` (CEL)?
3. В чем ключевая разница между `ownerReferences` и `finalizers`? Приведите пример, когда нужно использовать каждый из механизмов.
4. Какую угрозу безопасности предотвращает разделение ресурса на основной объект и `subresources.status`?
5. Что означает термин "Идемпотентность" в контексте функции `Reconcile()`?
6. Что такое "Server-side pruning" и как он помогает бороться с опечатками в YAML?

---

## Практические задания (отработка)

> Делайте задания на живом кластере; проверяйте себя командами.

1. **Pruning в действии:** Создайте CR `WebApp`, добавив в секцию `spec` ключ `environment: production`. Примените YAML. С помощью `kubectl get -o yaml` убедитесь, что поле `environment` бесследно исчезло.
2. **Написание схемы:** Откройте `manifests/crd.yaml` и измените валидацию: сделайте поле `host` (внутри `spec`) обязательным (`required`). Попробуйте применить `manifests/webapp.yaml` (где нет поля `host`) и добейтесь ошибки валидации.
3. **Зависший ресурс:** В манифест `webapp.yaml` вручную добавьте секцию `metadata.finalizers: ["lab/test-blocker"]`. Примените манифест. Затем попробуйте удалить: `kubectl delete webapp my-webapp`. Заметьте, что процесс завис. Откройте второй терминал, снимите финализатор с помощью `kubectl patch`, и убедитесь, что первый терминал завершил команду.
4. **Масштабирование:** Убедитесь, что команда `kubectl scale --replicas=4 webapp my-webapp` работает. Посмотрите, как изменилось поле `.spec.replicas`.
5. **Анализ логов:** Запустите `kopf run controller/operator.py -A`, измените образ `nginx:alpine` на `nginx:latest` с помощью `kubectl edit webapp my-webapp` и найдите в консоли оператора строчку о том, что Reconcile среагировал на изменения.

---

## Шпаргалка

```bash
# === Управление CRD ===
kubectl apply -f manifests/crd.yaml
kubectl get crd | grep example.com
kubectl api-resources --api-group=lab.example.com
# Посмотреть OpenAPI схему:
kubectl get crd webapps.lab.example.com -o yaml

# === Работа с Custom Resources ===
kubectl -n lab apply -f manifests/webapp.yaml
kubectl -n lab get wa -o wide
kubectl -n lab get webapp my-webapp -o yaml
# Масштабирование (благодаря subresources.scale):
kubectl -n lab scale webapp my-webapp --replicas=3

# === Диагностика Операторов ===
# Поиск операторов в кластере:
kubectl get crd | grep -E "monitoring.coreos.com|cert-manager|argoproj"
kubectl get pods -A | grep -i operator
# Удаление зависшего финализатора:
kubectl patch webapp my-webapp -p '{"metadata":{"finalizers":[]}}' --type=merge

# === Уборка ===
kubectl -n lab delete -f manifests/webapp.yaml
kubectl delete crd webapps.lab.example.com   # Каскадно удалит CRD И все существующие CR!
```

---

## Чему вы научились

В этом модуле вы научились:
- Глубокому пониманию принципов расширения API Kubernetes через CustomResourceDefinition.
- Механизмам строгой валидации ресурсов (OpenAPI, Server-side Pruning, CEL-правила).
- Архитектуре операторов: как работают Reconcile Loop, Informers, OwnerReferences и Finalizers.
- Интеграции собственных типов ресурсов со стандартным инструментарием `kubectl` (Printer columns, scale, status).
- Диагностике типичных проблем при работе с кастомными ресурсами и контроллерами.

## Уборка

```bash
# Останавливаем локальный процесс оператора, если он еще жив
pkill -f "kopf run" || true

# Удаляем ресурсы и сам CRD
kubectl -n lab delete -f manifests/webapp.yaml --ignore-not-found
kubectl delete crd webapps.lab.example.com --ignore-not-found
```


## Решения (Solutions)
В данном модуле добавлены подробные решения для сломанных сценариев в папке `solutions/`. Пожалуйста, изучите их для лучшего понимания.
