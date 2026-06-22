# Лабораторная работа 23: Kubernetes Gateway API

## Оглавление
<!-- TOC -->
- [Предварительные требования](#-)
- [Стартовая проверка](#-)
- [Часть 1: Введение в Gateway API и отличие от Ingress](#-1----gateway-api-----ingress)
  - [Теория для изучения перед частью](#----)
  - [1.1 Разделение ролей и ресурсов](#11---)
  - [1.2 Архитектура Gateway API](#12--gateway-api)
  - [1.3 Изучение GatewayClass](#13--gatewayclass)
- [Часть 2: Развертывание шлюза и базовый роутинг (HTTPRoute)](#-2-------httproute)
  - [Теория для изучения перед частью](#----1)
  - [2.1 Создание ресурса Gateway](#21---gateway)
  - [2.2 Создание приложения для маршрутизации](#22----)
  - [2.3 Настройка базового HTTPRoute](#23---httproute)
  - [2.4 Проверка прохождения трафика](#24---)
- [Часть 3: Продвинутая маршрутизация (Заголовки, Query параметры, Методы)](#-3------query--)
  - [Теория для изучения перед частью](#----2)
  - [3.1 Маршрутизация по HTTP-заголовкам](#31---http-)
  - [3.2 Маршрутизация по Query-параметрам](#32---query-)
  - [3.3 Маршрутизация по HTTP-методам](#33---http-)
- [Часть 4: Разделение трафика (Traffic Splitting / Canary Releases)](#-4----traffic-splitting--canary-releases)
  - [Теория для изучения перед частью](#----3)
  - [4.1 Подготовка второй версии приложения](#41----)
  - [4.2 Настройка весов (Weights) в HTTPRoute](#42---weights--httproute)
  - [4.3 Проверка и анализ распределения трафика](#43-----)
- [Часть 5: Модификация запросов (Filters: Rewrite, Redirect, Headers)](#-5----filters-rewrite-redirect-headers)
  - [Теория для изучения перед частью](#----4)
  - [5.1 Модификация заголовков (RequestHeaderModifier)](#51---requestheadermodifier)
  - [5.2 Перенаправление запросов (RequestRedirect)](#52---requestredirect)
  - [5.3 Перезапись пути (URLRewrite)](#53---urlrewrite)
- [Часть 6: Кросс-неймспейсовая маршрутизация и ReferenceGrant](#-6-----referencegrant)
  - [Теория для изучения перед частью](#----5)
  - [6.1 Проблема безопасности между командами](#61----)
  - [6.2 Разрешение доступа через ReferenceGrant](#62-----referencegrant)
- [Часть 7: TLS и интеграция с cert-manager](#-7-tls----cert-manager)
  - [Теория для изучения перед частью](#----6)
  - [7.1 Настройка HTTPS Listener в Gateway](#71--https-listener--gateway)
  - [7.2 Заказ сертификата через cert-manager](#72-----cert-manager)
- [Часть 8: Troubleshooting — боевые инциденты](#-8-troubleshooting---)
  - [Теория для изучения перед частью](#----7)
  - [Инцидент 1: Gateway не переходит в Programmed (ошибка класса)](#-1-gateway----programmed--)
  - [Инцидент 2: HTTPRoute имеет статус Accepted: False (ошибка parentRefs)](#-2-httproute---accepted-false--parentrefs)
  - [Инцидент 3: HTTPRoute Accepted: True, но возвращается 404 (нет Endpoints)](#-3-httproute-accepted-true---404--endpoints)
  - [Инцидент 4: Ошибка ReferenceGrant (Cross-Namespace Access Denied)](#-4--referencegrant-cross-namespace-access-denied)
- [Проверка модуля](#-)
- [Финальная карта ресурсов модуля](#---)
- [Теоретические вопросы (итоговые)](#--)
  - [Блок 1: Архитектура и роли](#-1---)
  - [Блок 2: Gateway и Listeners](#-2-gateway--listeners)
  - [Блок 3: HTTPRoute и маршрутизация](#-3-httproute--)
  - [Блок 4: Фильтры и безопасность](#-4---)
  - [Блок 5: Troubleshooting](#-5-troubleshooting)
- [Чему вы научились](#--)
- [Уборка](#)
- [Практические задания (отработка)](#--)
- [Шпаргалка](#)
<!-- /TOC -->


> ⏱ время ~45 мин · сложность 4/5 · пререквизиты: Трек 1 (Core), m04 (Ingress)

---

Цель всей работы: научиться осознанно управлять входящим трафиком в кластер с использованием современного стандарта Kubernetes Gateway API. Понять концепцию разделения ролей (инфраструктура, кластер-админ, разработчик), научиться настраивать Gateway, HTTPRoute, реализовывать canary-релизы (traffic splitting), фильтрацию запросов, кросс-неймспейсовую маршрутизацию и понимать процесс траблшутинга сложных сценариев.

> Все манифесты этой работы лежат в `manifests/`, поломки — в `broken/`,
> эталонные решения — в `solutions/`, автопроверка — в `verify/verify.sh`.
> README — это полный сценарий прохождения; манифесты применяются как файлы.

---

## Предварительные требования

Для работы необходим установленный контроллер Gateway API. Kubernetes "из коробки" поставляет только CRD (Custom Resource Definitions) для Gateway API, но не саму реализацию (контроллер). Существует множество реализаций: Istio, NGINX Gateway Fabric, Cilium, AWS ALB. В нашем стенде мы используем **Envoy Gateway** в конфигурации NodePort.

```bash
# kubeconfig нашего кластера (Kubespray); на другом стенде — свой путь/контекст
export KUBECONFIG=/root/.kube/kubespray.conf
# 1) Рабочий кластер и kubectl, который в него смотрит
kubectl version
kubectl cluster-info

# 2) Проверяем наличие установленных CRD Gateway API.
kubectl get crds | grep gateway.networking.k8s.io
```

Если CRD не найдены или контроллер не установлен, выполните скрипт инициализации:

```bash
# Запуск скрипта установки Envoy Gateway
bash ../../scripts/bootstrap/11-install-gateway-api.sh
```

> Скрипт установит Gateway API CRDs (v1), Envoy Gateway Controller и создаст базовый `GatewayClass` с именем `eg`. Процесс может занять несколько минут.

Создадим отдельный namespace для лабораторной работы:

```bash
# 3) Namespace для всех ресурсов лабы
kubectl create ns lab-gateway --dry-run=client -o yaml | kubectl apply -f -

# Удобный алиас на время работы
alias kg='kubectl -n lab-gateway'
```

---

## Стартовая проверка

Убедитесь, что контроллер работает и кластер поддерживает новые ресурсы. Gateway API вводит новые кластерные объекты.

```bash
# Проверяем наличие GatewayClass
kubectl get gatewayclasses
```

Ожидаемый вывод (статус ACCEPTED: True):
```
NAME   CONTROLLER                                      ACCEPTED   AGE
eg     gateway.envoyproxy.io/gatewayclass-controller   True       10m
```

Проверим поды контроллера Envoy Gateway (он разворачивается в своем namespace):
```bash
kubectl get pods -n envoy-gateway-system
```

Ожидаемый вывод (контроллер должен быть в статусе Running):
```
NAME                               READY   STATUS    RESTARTS   AGE
envoy-gateway-7b9cd84b49-xyz12     1/1     Running   0          10m
```

> **Важно:** Если `GatewayClass` не показывает ACCEPTED: True, это означает, что контроллер не запустился или не готов принимать конфигурации. Продолжать лабораторную бессмысленно, пока статус не станет True.

---

## Часть 1: Введение в Gateway API и отличие от Ingress

### Теория для изучения перед частью

- Почему `Ingress` устарел и был заархивирован
- Ролевая модель Gateway API: Provider, Operator, Developer
- Какие CRD входят в стандарт Gateway API (GatewayClass, Gateway, Route)
- В чем разница между `HTTPRoute`, `TCPRoute` и `GRPCRoute`

#### 1.1 Разделение ролей и ресурсов

Стандартный ресурс `Ingress` (появившийся в k8s 1.1) был официально заархивирован сообществом: он поддерживается, но больше не получает новых функций (frozen). Ingress имел ряд архитектурных недостатков:

1. **Слабая переносимость (Portability):** почти все продвинутые функции (rewrite, rate-limit, auth) настраивались через нестандартные `annotations` (например, `nginx.ingress.kubernetes.io/rewrite-target`). Переезд с NGINX на HAProxy Ingress требовал переписывания всех аннотаций в манифестах разработчиков.
2. **Отсутствие разделения ролей:** разработчик приложения (настраивающий пути) и администратор (настраивающий TLS, порты и домены) редактировали один и тот же монолитный манифест `Ingress`. При ошибке разработчика мог упасть общий Ingress для всего домена.
3. **Бедность возможностей:** Ingress изначально проектировался только для HTTP/HTTPS и не поддерживал разделение трафика (traffic splitting по весам), TCP/UDP маршрутизацию, маршрутизацию по заголовкам или gRPC.

Новый стандарт **Gateway API** решает эти проблемы путем разделения конфигурации на независимые ресурсы, которые строго типизированы и отражают роли инженеров в организации:

| Роль (Persona) | Ресурс | Зона ответственности |
|----------------|--------|----------------------|
| **Провайдер инфраструктуры** (Infrastructure Provider) | `GatewayClass` | Выбирает тип балансировщика (AWS ALB, NGINX, Envoy, Cilium). Разворачивает базовую инфраструктуру. |
| **Кластерный администратор** (Cluster Operator) | `Gateway` | Создает точку входа трафика в кластер. Указывает, какие порты слушать, какие публичные IP выделять, и заказывает TLS-сертификаты. Распределяет права (каким namespace можно к нему подключаться). |
| **Разработчик приложения** (Application Developer) | `HTTPRoute`, `TCPRoute`, `GRPCRoute` | Описывает конкретные правила маршрутизации (пути, заголовки, веса) для своего сервиса. Вообще не думает про порты шлюза и SSL сертификаты. |

#### 1.2 Архитектура Gateway API

Взаимосвязь ресурсов строится иерархически:

```text
  [Инфраструктура]            GatewayClass
                                   ▲
                                   │ ссылается на класс
  [Кластер Администратор]        Gateway  (например, port 80, 443)
                                   ▲
                                   │ parentRefs (кто принимает трафик)
  [Разработчик]               ┌────┴────┐
                          HTTPRoute   HTTPRoute
                          (path /a)   (path /b)
                              │           │ backendRefs
                              ▼           ▼
  [Приложение]             Service     Service
```

- **GatewayClass** — это абстракция (шаблон). Аналог `StorageClass` для дисков.
- **Gateway** — это экземпляр (конкретная точка входа). Когда создается Gateway, контроллер (в нашем случае Envoy) материализует его, создавая реальный прокси-сервер (Pod Envoy) и Service типа LoadBalancer/NodePort для него.
- **Route** (`HTTPRoute`, `TCPRoute` и т.д.) — это правила маршрутизации, которые "привязываются" к шлюзу и говорят: "если пришел запрос на путь `/api`, отправь его в мой сервис `api-svc`".

#### 1.3 Изучение GatewayClass

Давайте посмотрим на наш кластерный `GatewayClass`, который мы будем использовать на протяжении всей работы.

```bash
kubectl describe gatewayclass eg
```

Вывод покажет важную секцию:
```yaml
Name:         eg
Namespace:    
Controller:   gateway.envoyproxy.io/gatewayclass-controller
...
```
`Controller: gateway.envoyproxy.io/gatewayclass-controller` означает, что любой ресурс `Gateway`, ссылающийся на класс `eg`, будет подхвачен контроллером Envoy Gateway.

---

## Часть 2: Развертывание шлюза и базовый роутинг (HTTPRoute)

### Теория для изучения перед частью

- Ресурс `Gateway`: секция `listeners` (уникальное имя, протокол, порт).
- Контроль доступа в `Gateway`: секция `allowedRoutes` — кому разрешено прикреплять маршруты к этому шлюзу.
- Ресурс `HTTPRoute`: секция `parentRefs` (связь с Gateway) и секция `rules` (`matches`, `backendRefs`).
- Условия (Conditions): как контроллеры сообщают о статусе принятия ресурсов (`Programmed`, `Accepted`).

**Цель:** создать единую точку входа (Gateway) и направить HTTP-трафик на простое тестовое приложение с помощью HTTPRoute.

**Ресурсы:** 
- `manifests/01-basic-routing/gateway.yaml`
- `manifests/01-basic-routing/app.yaml`
- `manifests/01-basic-routing/httproute.yaml`

---

### 2.1 Создание ресурса Gateway

Для начала, в роли администратора кластера, мы создаем шлюз, который будет слушать входящий трафик.

```yaml
# manifests/01-basic-routing/gateway.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: demo-gateway
  namespace: lab-gateway
spec:
  gatewayClassName: eg    # Связь с инфраструктурным провайдером
  listeners:
  - name: http            # Уникальное имя слушателя
    protocol: HTTP        # Протокол (HTTP, HTTPS, TCP, UDP, TLS)
    port: 80              # Слушать на порту 80
    allowedRoutes:        # Политика безопасности: кому можно подключаться
      namespaces:
        from: Same        # Разрешить прикреплять маршруты только из этого же namespace
```

```bash
# Применим манифест Gateway
kubectl apply -f manifests/01-basic-routing/gateway.yaml
```

Процесс материализации шлюза занимает некоторое время. Контроллер Envoy видит объект `Gateway` и:
1. Запускает новый Deployment с Envoy Proxy (Data Plane).
2. Создает для него Service, чтобы выставить его наружу.
3. Генерирует конфиги Envoy (через xDS API).

Дождемся, пока шлюз станет готов:
```bash
kubectl wait --timeout=2m -n lab-gateway gateway/demo-gateway --for=condition=Programmed
```

Проверим статус шлюза:
```bash
kubectl get gateway -n lab-gateway demo-gateway
```

Ожидаемый статус:
```
NAME           CLASS   ADDRESS         PROGRAMMED   AGE
demo-gateway   eg      192.168.1.100   True         30s
```
> **Programmed = True** означает, что конфигурация шлюза успешно применена на реальном балансировщике и порты открыты. Адрес — это IP, по которому доступен шлюз.

Убедимся, что дата-плейн Envoy (само тело балансировщика) реально запущен:
```bash
kubectl get pods -n envoy-gateway-system | grep demo-gateway
```
Вы увидите pod с именем вроде `envoy-lab-gateway-demo-gateway-abcde-12345`. Это и есть Nginx/Envoy прокси, который обслуживает наш `Gateway`.

### 2.2 Создание приложения для маршрутизации

В роли разработчика развернем приложение, к которому мы хотим предоставить доступ.

```bash
# Запустим Deployment и Service версии v1
kubectl apply -f manifests/01-basic-routing/app.yaml

# Дождемся готовности подов
kubectl -n lab-gateway rollout status deploy/store-v1 --timeout=60s
```

### 2.3 Настройка базового HTTPRoute

Чтобы направить трафик со шлюза в наше приложение, разработчик создает `HTTPRoute`.

```yaml
# manifests/01-basic-routing/httproute.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: store-route
  namespace: lab-gateway
spec:
  parentRefs:
  - name: demo-gateway    # К какому шлюзу "пристегнуть" этот маршрут
    namespace: lab-gateway
  rules:
  - matches:
    - path:
        type: PathPrefix  # Совпадение по префиксу пути (все, что начинается со /store)
        value: /store
    backendRefs:
    - name: store-v1      # Куда направить трафик (Service name)
      port: 80            # Порт Service
```

```bash
# Применим манифест HTTPRoute
kubectl apply -f manifests/01-basic-routing/httproute.yaml
```

Давайте изучим статус маршрута (это важнейший навык для troubleshooting):
```bash
kubectl get httproute -n lab-gateway store-route
```
Вы должны увидеть `HOSTNAMES: *` и `AGE: <time>`.

Посмотрим детальное состояние, которое возвращает контроллер:
```bash
kubectl describe httproute store-route -n lab-gateway | grep -A 10 "Status:"
```
Ожидаемый вывод:
```yaml
Status:
  Parents:
    Conditions:
      Last Transition Time:  2023-10-25T10:00:00Z
      Message:               Route is accepted
      Reason:                Accepted
      Status:                True
      Type:                  Accepted
      ...
      Reason:                ResolvedRefs
      Status:                True
      Type:                  ResolvedRefs
```
- **Accepted: True** (шлюз принял маршрут, правила безопасности пройдены).
- **ResolvedRefs: True** (backend сервис существует, поды найдены).

### 2.4 Проверка прохождения трафика

В нашем стенде Envoy Gateway Controller настроен на публикацию шлюзов через `NodePort` Service (в реальном облаке это обычно `LoadBalancer`, и вы бы просто использовали его внешний IP).

Давайте динамически найдем этот NodePort порт и IP ноды:
```bash
# Узнаем порт HTTP-слушателя шлюза на нодах
NODE_PORT=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=demo-gateway -o jsonpath='{.items[0].spec.ports[?(@.name=="http")].nodePort}')

# Узнаем внутренний IP адрес первой ноды
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

echo "Gateway доступен по адресу: http://$NODE_IP:$NODE_PORT"
```

Сделаем тестовый запрос по пути `/store`, который мы определили в `matches`:
```bash
curl -s http://$NODE_IP:$NODE_PORT/store
```
Ожидаемый ответ от пода `store-v1`:
```
Store V1
```

Если мы запросим другой путь, получим ошибку от шлюза:
```bash
curl -s -I http://$NODE_IP:$NODE_PORT/unknown-path | head -n 1
```
Ожидаемый ответ:
```
HTTP/1.1 404 Not Found
```

> **Важно:** 404 возвращает сам Envoy Proxy, потому что для пути `/unknown-path` мы не определили ни одного `HTTPRoute`. Это нормальное поведение балансировщика, когда нет совпадений.

---

## Часть 3: Продвинутая маршрутизация (Заголовки, Query параметры, Методы)

### Теория для изучения перед частью

- В `HTTPRoute` блок `matches` — это массив условий. Разные элементы массива объединяются по логическому ИЛИ (OR).
- Внутри одного конкретного блока `match` условия (`path`, `headers`, `queryParams`, `method`) объединяются по логическому И (AND). Чтобы сработало правило, запрос должен удовлетворять ВСЕМ условиям внутри `match`.
- Типы совпадений (Match Types): `Exact` (строгое равенство), `RegularExpression` (регулярки, поддерживаются не всеми прокси), `PathPrefix` (все, что вложено в префикс).

Gateway API предоставляет богатые возможности маршрутизации L7 (HTTP) прямо "из коробки", без аннотаций, как это было в Ingress.

---

### 3.1 Маршрутизация по HTTP-заголовкам

Давайте настроим маршрут, который будет направлять трафик на сервис `store-v1` только если передан специальный заголовок `X-Beta-Access: true`.

```yaml
# manifests/03-advanced-routing/httproute-headers.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: header-route
  namespace: lab-gateway
spec:
  parentRefs:
  - name: demo-gateway
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /beta
      headers:
      - name: X-Beta-Access
        type: Exact
        value: "true"
    backendRefs:
    - name: store-v1
      port: 80
```

```bash
# Применим маршрут с заголовками
kubectl apply -f manifests/03-advanced-routing/httproute-headers.yaml
```

Проверим работу:
```bash
# Запрос без заголовка (шлюз не найдет совпадения -> 404)
curl -s -I http://$NODE_IP:$NODE_PORT/beta | head -n 1
# HTTP/1.1 404 Not Found

# Запрос с правильным заголовком
curl -s -H "X-Beta-Access: true" http://$NODE_IP:$NODE_PORT/beta
# Store V1
```

### 3.2 Маршрутизация по Query-параметрам

Часто нужно маршрутизировать трафик на основе GET-параметров в URL, например `?user=admin` или `?region=eu`.

```yaml
# manifests/03-advanced-routing/httproute-query.yaml (фрагмент)
  - matches:
    - path:
        type: PathPrefix
        value: /admin
      queryParams:
      - name: role
        type: Exact
        value: admin
```

```bash
kubectl apply -f manifests/03-advanced-routing/httproute-query.yaml
```

Проверка:
```bash
# Параметр не совпадает (или отсутствует)
curl -s -I http://$NODE_IP:$NODE_PORT/admin?role=guest | head -n 1
# HTTP/1.1 404 Not Found

# Строгое совпадение query-параметра
curl -s http://$NODE_IP:$NODE_PORT/admin?role=admin
# Store V1
```

### 3.3 Маршрутизация по HTTP-методам

Gateway API легко разделяет GET, POST, PUT, DELETE запросы на разные бекенды, что идеально для REST API (например, отправлять GET в кеш, а POST в write-реплику базы).

```yaml
# Фрагмент манифеста
  - matches:
    - path:
        type: PathPrefix
        value: /api
      method: POST
```

> **Совет:** Все эти условия (заголовки, методы, query) встроены в ядро стандарта Gateway API. Контроллер (Envoy Gateway) сам валидирует их и транслирует в конфигурацию нижележащего прокси (в Envoy xDS API), что делает их 100% переносимыми на любой другой контроллер, поддерживающий Gateway API.

---

## Часть 4: Разделение трафика (Traffic Splitting / Canary Releases)

### Теория для изучения перед частью

- Канареечные релизы (Canary): методология, при которой новая версия приложения (v2) получает лишь небольшую долю реального трафика (например, 5%), чтобы убедиться в отсутствии багов.
- Поле `weight` в `backendRefs`: веса не обязаны суммироваться в 100. Это просто пропорции.
- Формула расчета: доля бэкенда = (его вес / сумма всех весов).
- Если у одного backendRef вес равен `0`, трафик на него не маршрутизируется вообще.

В Ingress для canary-релизов приходилось писать сложные и хрупкие аннотации (вроде `nginx.ingress.kubernetes.io/canary-weight: "10"`). В Gateway API это базовая, встроенная фича.

---

### 4.1 Подготовка второй версии приложения

Развернем версию 2 нашего приложения (оно отвечает строкой `Store V2`).

```bash
# Применяем v2
kubectl apply -f manifests/02-traffic-splitting/app-v2.yaml
kubectl -n lab-gateway rollout status deploy/store-v2 --timeout=60s
```

Убедимся, что поды v2 запущены:
```bash
kubectl get pods -n lab-gateway -l app=store,version=v2
```

### 4.2 Настройка весов (Weights) в HTTPRoute

Мы отредактируем наш маршрут `store-route`, чтобы 90% трафика шло на старую стабильную `store-v1`, а 10% — на новую `store-v2`.

```yaml
# manifests/02-traffic-splitting/httproute-split.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: store-route
  namespace: lab-gateway
spec:
  parentRefs:
  - name: demo-gateway
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /store
    backendRefs:
    - name: store-v1
      port: 80
      weight: 90    # Вероятность: 90 / (90 + 10) = 90%
    - name: store-v2
      port: 80
      weight: 10    # Вероятность: 10 / (90 + 10) = 10%
```

```bash
# Применим маршрут с весами
kubectl apply -f manifests/02-traffic-splitting/httproute-split.yaml
```

### 4.3 Проверка и анализ распределения трафика

Сделаем 20 последовательных запросов и сгруппируем ответы для подсчета статистики:

```bash
for i in {1..20}; do curl -s http://$NODE_IP:$NODE_PORT/store; done | sort | uniq -c
```

Примерный ожидаемый результат:
```
     18 Store V1
      2 Store V2
```

> **Внимание:** Разделение трафика в Envoy работает на основе вероятностных алгоритмов прокси-сервера. На малой выборке запросов (10-20) вы можете получить соотношение 8:2, 10:0 и т.д. Это нормально. На объемах в тысячи запросов распределение будет стремиться к идеальным 90% / 10%.

Чтобы переключить весь трафик на `v2` (завершение canary релиза), достаточно изменить веса: `store-v1: 0`, `store-v2: 100` (или `store-v1: 0`, `store-v2: 1`).

---

## Часть 5: Модификация запросов (Filters: Rewrite, Redirect, Headers)

### Теория для изучения перед частью

- Секция `filters` в `HTTPRoute` (`rules[].filters`), обрабатываемая до отправки запроса в backend.
- `RequestHeaderModifier`: добавление, удаление, замена заголовков HTTP-запроса. Часто используется для добавления корреляционных ID или флагов для приложения.
- `RequestRedirect`: перенаправление клиента (HTTP 301/302) на другой URL, порт или схему (например, перехват HTTP и редирект на HTTPS).
- `URLRewrite`: изменение пути запроса (strip prefix) "на лету" перед отправкой в бекенд.

---

### 5.1 Модификация заголовков (RequestHeaderModifier)

Добавим заголовок `X-Injected-By: Gateway-API` во все запросы к `/store`, чтобы бекенд знал, через какой шлюз прошел трафик.

```yaml
# Фрагмент правила HTTPRoute с фильтром
    filters:
    - type: RequestHeaderModifier
      requestHeaderModifier:
        add:
        - name: X-Injected-By
          value: Gateway-API
        remove:
        - X-Old-Header
```

Применяя такой манифест, Envoy proxy сам добавит этот заголовок в пакет до отправки в pod `store-v1`.

### 5.2 Перенаправление запросов (RequestRedirect)

Сделаем так, чтобы устаревший путь `/old-store` автоматически перенаправлял клиента на новый `/store` с кодом `301 Moved Permanently`.

```yaml
# manifests/05-filters/httproute-redirect.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: redirect-route
  namespace: lab-gateway
spec:
  parentRefs:
  - name: demo-gateway
  rules:
  - matches:
    - path:
        type: Exact
        value: /old-store
    filters:
    - type: RequestRedirect
      requestRedirect:
        path:
          type: ReplaceFullPath     # Заменить весь путь
          replaceFullPath: /store
        statusCode: 301             # Вернуть HTTP статус перенаправления
```

```bash
kubectl apply -f manifests/05-filters/httproute-redirect.yaml

# Проверим HTTP-заголовки ответа
curl -s -I http://$NODE_IP:$NODE_PORT/old-store | grep -E "HTTP|location"
```

Ожидаемый вывод:
```
HTTP/1.1 301 Moved Permanently
location: http://192.168.1.100:32145/store
```
Запрос даже не доходит до бекенда, шлюз сам формирует 301 ответ.

### 5.3 Перезапись пути (URLRewrite)

Очень частый кейс: приложение (внутри контейнера) ожидает запросы на корень `/`, но в кластере мы выставляем его наружу по пути `/api/v1/`. Нам нужно "отрезать" префикс до того, как запрос попадет в контейнер (Strip Prefix).

```yaml
# Фрагмент манифеста URLRewrite
    filters:
    - type: URLRewrite
      urlRewrite:
        path:
          type: ReplacePrefixMatch  # Изменить ту часть, которая совпала в 'matches'
          replacePrefixMatch: /     # Заменить ее на /
```
В Ingress это достигалось мутными регулярными выражениями в `nginx.ingress.kubernetes.io/rewrite-target: /$1`. В Gateway API это встроенная, строго типизированная функциональность `URLRewrite`.

---

## Часть 6: Кросс-неймспейсовая маршрутизация и ReferenceGrant

### Теория для изучения перед частью

- Разделение зон ответственности (Namespace Isolation).
- Что такое `ReferenceGrant` и зачем он нужен.
- Направление ссылок: `from` (кто запрашивает доступ) и `to` (к какому ресурсу доступ открывается).

В отличие от старого Ingress, который позволял легко направлять трафик на сервисы из любых неймспейсов (что часто приводило к дырам в безопасности в multi-tenant кластерах), Gateway API **строго контролирует безопасность между неймспейсами**.

По умолчанию, `HTTPRoute` в `namespace-A` не может направлять трафик (`backendRefs`) в Service, находящийся в `namespace-B`. Чтобы это разрешить, администратор (или владелец) `namespace-B` должен явно создать ресурс `ReferenceGrant`.

### 6.1 Проблема безопасности между командами

Представим:
- Команда "Фронтенд" (namespace `frontend`) владеет `HTTPRoute`.
- Команда "Бэкенд" (namespace `backend`) владеет базой данных `db-service` и API `api-service`.

Если фронтенд может произвольно прописывать `backendRefs: [{name: db-service, namespace: backend}]`, он получит прямой доступ к базе, в обход API! Gateway API это блокирует.

### 6.2 Разрешение доступа через ReferenceGrant

Владелец `namespace-B` создает манифест-разрешение:

```yaml
# Пример ReferenceGrant (создается в namespace, куда мы разрешаем доступ)
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-from-frontend
  namespace: backend        # Применяется в целевом namespace
spec:
  from:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    namespace: frontend     # Кто просит доступ
  to:
  - group: ""               # Базовая группа (core)
    kind: Service           # К чему даем доступ
```
Только после создания этого ресурса `HTTPRoute` из `frontend` получит статус `ResolvedRefs: True` для сервисов в `backend`. Это мощный механизм изоляции (tenant isolation).

---

## Часть 7: TLS и интеграция с cert-manager

### Теория для изучения перед частью

- Роль `TLS` в `Gateway`: секция `listeners[].tls`.
- Режим терминирования: `mode: Terminate` (расшифровка SSL происходит на самом шлюзе) vs `mode: Passthrough` (зашифрованный трафик передается сквозь шлюз прямо в pod).
- Интеграция с `cert-manager`: автоматический заказ сертификатов аннотацией на самом Gateway.

Как и `Ingress`, Gateway API поддерживает автоматический заказ TLS-сертификатов (Let's Encrypt и др.) через `cert-manager`. Однако есть ключевое отличие в распределении ролей.

В Ingress разработчик запрашивал сертификат прямо в манифесте `Ingress`. В Gateway API за сертификаты, слушатели и порты отвечает **Администратор кластера** через манифест `Gateway`. Разработчик в своем `HTTPRoute` даже не подозревает, используется ли HTTP или HTTPS для обслуживания его пути.

### 7.1 Настройка HTTPS Listener в Gateway

```yaml
# Принципиальная схема Gateway с TLS Termination
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: demo-gateway-tls
spec:
  gatewayClassName: eg
  listeners:
  - name: https             # Создаем второй слушатель
    protocol: HTTPS         # Указываем протокол HTTPS
    port: 443
    hostname: "api.example.com"
    tls:
      mode: Terminate       # Шлюз расшифрует трафик
      certificateRefs:
      - name: api-tls-cert  # Имя Secret с TLS сертификатом
```

### 7.2 Заказ сертификата через cert-manager

`cert-manager` версии 1.5+ нативно отслеживает ресурсы `Gateway`. Если вы добавите специальную аннотацию на объект `Gateway`, cert-manager автоматически сгенерирует ресурс `Certificate` и сохранит ключи в секрет `api-tls-cert`.

```yaml
metadata:
  name: demo-gateway-tls
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
```

*В рамках данного лабораторного стенда (без реального публичного домена и DNS) мы не разворачиваем HTTPS практически, но структура выше показывает, как элегантно TLS изолирован от разработчиков (HTTPRoute).*

---

## Часть 8: Troubleshooting — боевые инциденты

### Теория для изучения перед частью

- Фазы Gateway: `Programmed` (готов ли прокси слушать порты) vs `Accepted`.
- Условия (Conditions) в HTTPRoute: `Accepted` (согласился ли шлюз принять маршрут), `ResolvedRefs` (смог ли шлюз найти указанные Service).
- Основные утилиты диагностики: `kubectl describe gateway`, `kubectl describe httproute`.
- Логи Envoy контроллера.

#### Алгоритм диагностики Gateway API

```text
Трафик не доходит до приложения (Connection Refused, 404, 503)
│
├─ Gateway в статусе Programmed = False ? ──► kubectl describe gateway <name>
│     ├─ Контроллер Gateway API не запущен / не найден GatewayClass
│     ├─ Порт конфликтует (Port collision - уже занят другим Gateway)
│     └─ Ошибка валидации Listener
│
├─ HTTPRoute Accepted = False ? ───────────► kubectl describe httproute <name>
│     ├─ Указан неверный parentRefs (опечатка в имени или namespace Gateway)
│     ├─ Gateway явно не разрешает allowedRoutes для этого namespaces
│     └─ Конфликт hostname
│
├─ HTTPRoute ResolvedRefs = False ? ───────► kubectl describe httproute <name>
│     ├─ BackendRef ссылается на несуществующий Service (опечатка)
│     ├─ BackendRef указывает на Service в другом namespace без ReferenceGrant
│     └─ Service не имеет указанного порта (или опечатка в port)
│
└─ Все True, но возвращается 404/503 ? ────► Проверьте:
      ├─ Совпадают ли matches (в пути, методе, заголовках)
      ├─ Есть ли у Service живые Endpoints (поды в статусе Ready) -> kubectl get endpoints
      └─ Посмотрите логи контроллера дата-плейна (Envoy pods)
```

---

**Цель:** отработать диагностику сломанных маршрутов и шлюзов на практике.

---

### Инцидент 1: Gateway не переходит в Programmed (ошибка класса)

**Воспроизведение:**
Мы попытаемся создать шлюз, который ссылается на неизвестный инфраструктурный класс.

```bash
kubectl apply -f broken/scenario-01/gateway.yaml
# Ждем пару секунд
kubectl get gateway -n lab-gateway broken-gw
```
Вывод покажет `PROGRAMMED: Unknown` или `False`. Шлюз не работает.

**Диагностика:**
```bash
kubectl describe gateway broken-gw -n lab-gateway | grep -A 10 Conditions
```
В событиях и условиях (Conditions) вы увидите сообщение, что `GatewayClass "unknown-class" not found`. Так как класса нет, ни один контроллер в кластере не берет на себя управление этим шлюзом.

**Решение:**
Измените класс на существующий `eg` или просто удалите сломанный шлюз.
```bash
kubectl delete -f broken/scenario-01/gateway.yaml
```

### Инцидент 2: HTTPRoute имеет статус Accepted: False (ошибка parentRefs)

Частая ошибка разработчиков — опечатка в имени `Gateway` при привязывании маршрута.

**Воспроизведение:**
```bash
kubectl apply -f broken/scenario-02/httproute.yaml
kubectl get httproute broken-route -n lab-gateway
```

**Диагностика:**
```bash
kubectl describe httproute broken-route -n lab-gateway | grep -A 5 Status
```
В секции `Conditions` для ParentRef вы увидите:
```yaml
Type: Accepted
Status: False
Reason: InvalidParentRef
Message: Gateway "typo-gateway" not found
```
Маршрут стал сиротой. Шлюз `typo-gateway` не существует, поэтому маршрут никогда не будет применен.

**Решение:**
Отредактируйте манифест `HTTPRoute`, указав корректное имя шлюза `demo-gateway` в блоке `parentRefs`.

### Инцидент 3: HTTPRoute Accepted: True, но возвращается 404 (нет Endpoints)

**Воспроизведение:**
```bash
kubectl apply -f broken/scenario-03/httproute.yaml

# Попробуем сделать запрос на прописанный там путь
curl -s -I http://$NODE_IP:$NODE_PORT/broken-path | head -n 1
```
Возвращается `HTTP/1.1 503 Service Unavailable` (Envoy говорит "no healthy upstream").

**Диагностика:**
Маршрут принят шлюзом (Accepted: True), но куда он указывает?
```bash
kubectl describe httproute broken-endpoints-route -n lab-gateway | grep -A 5 ResolvedRefs
```
Если условие `ResolvedRefs` имеет статус `False` с Reason `BackendNotFound`, это значит, что целевой `Service` не существует. Действительно, если проверить:
```bash
kubectl get svc -n lab-gateway missing-service
# Error from server (NotFound): services "missing-service" not found
```
Envoy прокси получает трафик для `/broken-path`, но у него нет валидных IP адресов подов (endpoints) для отправки трафика.

### Инцидент 4: Ошибка ReferenceGrant (Cross-Namespace Access Denied)

Если вы попробуете маршрутизировать трафик в Service из чужого namespace без создания там `ReferenceGrant`, `HTTPRoute` выдаст ошибку `ResolvedRefs: False`, с Reason `RefNotPermitted`. Добавление `ReferenceGrant` мгновенно устранит проблему (состояние перейдет в True).

---

## Проверка модуля

Выполните скрипт автопроверки. Он убедится, что HTTPRoute настроен корректно, работает traffic splitting на демо-приложения, и шлюз доступен.
```bash
bash verify/verify.sh
```
> Скрипт проверит доступность Gateway, статусы HTTPRoute (`Accepted=True`), и корректность ответов от подов (должно быть наличие как `Store V1`, так и `Store V2`).

---

## Финальная карта ресурсов модуля

| Объект | Тип | Роль (Persona) | Что делает |
|--------|-----|----------------|------------|
| `eg` | `GatewayClass` | Провайдер Инфраструктуры | Указывает, что контроллер — Envoy. Шаблон балансировщика. |
| `demo-gateway` | `Gateway` | Админ кластера | Слушает порт 80, управляет общими политиками безопасности (AllowedRoutes). Инстанцирует реальный Envoy-прокси. |
| `store-route` | `HTTPRoute` | Разработчик | Направляет запросы префикса `/store` в сервисы `store-v1` и `store-v2` с распределением трафика 90/10. |
| `store-v1`/`v2`| `Deployment`/`Service`| Разработчик | Сами целевые приложения (Endpoints). |

---

## Теоретические вопросы (итоговые)

### Блок 1: Архитектура и роли
1. Почему Gateway API использует модель ролевого доступа и разделяет конфигурацию на GatewayClass, Gateway и HTTPRoute, в отличие от единого манифеста Ingress? Приведите пример проблемы из реальной практики, которую это решает.
2. В чем принципиальная разница между ресурсами `GatewayClass` и `Gateway`?
3. Какой именно контроллер (ingress/gateway-реализация) материализует объекты Gateway в данной лаборатории?

### Блок 2: Gateway и Listeners
4. За что отвечает блок `listeners` в манифесте `Gateway`?
5. Что делает секция `allowedRoutes` внутри слушателя? Что произойдет, если разработчик из чужого namespace попробует прикрепить маршрут?
6. На чьей стороне происходит настройка портов и заказ TLS-сертификатов: в `Gateway` или в `HTTPRoute`? Обоснуйте архитектурное решение.

### Блок 3: HTTPRoute и маршрутизация
7. Как `HTTPRoute` логически привязывается к `Gateway` (какое поле используется)?
8. Как Gateway API объединяет условия внутри одного элемента массива `matches` (по И или по ИЛИ)?
9. Каков механизм разделения трафика (Traffic Splitting) в Gateway API? Зависит ли он от "магических" аннотаций, как это было в Ingress?

### Блок 4: Фильтры и безопасность
10. Какой встроенный фильтр (filter type) нужно использовать, чтобы перенаправить HTTP-трафик на новый путь с кодом ответа 301?
11. Какой встроенный фильтр позволяет изменить (перезаписать) URL до отправки запроса в контейнер приложения?
12. Для чего нужен `ReferenceGrant` в Gateway API? Какую критическую уязвимость multi-tenant кластеров он устраняет?

### Блок 5: Troubleshooting
13. О чем говорит статус объекта Gateway `Programmed: False`? Приведите 2 возможные причины.
14. Где искать причину ошибки и какой `Reason` будет указан, если `HTTPRoute` ссылается на Service, которого не существует?

---

## Чему вы научились

В этом глубоком модуле вы успешно:
- Освоили архитектуру современного и мощного стандарта маршрутизации Gateway API.
- Поняли ролевую модель: разделение зон ответственности инженеров инфраструктуры, кластерных администраторов и команд разработчиков.
- Развернули Gateway на базе Envoy и настроили базовые и продвинутые (по заголовкам, параметрам) HTTP-маршруты.
- Настроили нативное разделение трафика (canary releases / traffic splitting) без использования костыльных регулярных выражений и аннотаций.
- Изучили механизмы глубокой модификации HTTP-запросов на лету с помощью строгих встроенных фильтров (Redirects, URLRewrites, HeaderModifiers).
- Изучили механизмы Tenant Isolation с помощью ресурса `ReferenceGrant`.
- Отработали на практике 4 сценария боевых инцидентов и научились диагностировать статус-флаги API (`Programmed`, `Accepted`, `ResolvedRefs`).

---

## Уборка

Очистите ресурсы после завершения работы, чтобы не расходовать память и CPU локального стенда:

```bash
bash verify/cleanup.sh
```
*(Этот автоматический скрипт удалит все созданные в рамках лаборатории ресурсы: Gateway, HTTPRoutes, Deployments, Services, и полностью удалит namespace `lab-gateway`).*

---

## Практические задания (отработка)

> Проверяйте ваши собственные конфигурации на живом кластере. Вы можете создать свои файлы в директории `manifests/practice/`.

1. **Traffic Splitting:** Измените веса в `httproute-split.yaml` на 50/50, примените обновленный манифест и проверьте через скрипт с циклом `curl`, что ответы от `v1` и `v2` чередуются равномерно (примерно 10:10 на выборке из 20 запросов).
2. **Диагностика:** Изучите полный вывод команды `kubectl describe httproute store-route -n lab-gateway` и найдите массив `Status`. Посмотрите, какие именно `Conditions` установлены для связи с `demo-gateway` и какое время перехода (Last Transition Time) указано.
3. **Маршрутизация по заголовку:** Создайте абсолютно новое правило `HTTPRoute`, которое маршрутизирует трафик только при наличии HTTP-заголовка `User-Type: Premium` на быстрый сервис `store-v2`. Если заголовка нет (дефолтный трафик) — маршрут должен вести на `store-v1`.
4. **Фильтрация URL:** Настройте фильтр `URLRewrite`, который берет входящий путь `/api/v1/users` и превращает его в `/users` непосредственно перед передачей пакета в бекенд Service.

---

## Шпаргалка

```bash
# Просмотр основных ресурсов Gateway API (кратко)
kubectl get gatewayclasses (или сокращенно gwc)
kubectl get gateways -A    (или gtw)
kubectl get httproutes -A

# Проверка статуса (Programmed для Gateway, Accepted для Route)
kubectl get gateway demo-gateway -n lab-gateway -o wide
kubectl get httproute store-route -n lab-gateway -o wide

# Глубокая диагностика (ошибки привязки parentRefs, порты, TLS, endpoints)
kubectl describe gateway <gateway-name> -n <namespace>
kubectl describe httproute <route-name> -n <namespace>

# Как узнать IP/Port шлюза (если он опубликован через NodePort, пример для Envoy)
kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=demo-gateway
```
