# Лабораторная работа 23: Kubernetes Gateway API

## Оглавление
<!-- TOC -->
- [Предварительные требования](#-)
- [Стартовая проверка](#-)
- [Часть 1: Введение и отличие от Ingress](#-1----ingress)
- [Часть 2: Базовый роутинг (HTTPRoute)](#-2---httproute)
- [Часть 3: Traffic Splitting (Canary Releases)](#-3-traffic-splitting-canary-releases)
- [Часть 4: TLS и интеграция с cert-manager](#-4-tls----cert-manager)
- [Проверка модуля](#-)
- [Финальная карта ресурсов модуля](#---)
- [Теоретические вопросы (итоговые)](#--)
- [Практические задания (отработка)](#--)
- [Шпаргалка](#)
- [Чему вы научились](#--)
- [Уборка](#)
<!-- /TOC -->

> ⏱ время ~35 мин · сложность 4/5 · пререквизиты: Трек 1 (Core), m04 (Ingress)

Цель: изучить современный стандарт маршрутизации трафика Kubernetes Gateway API, который пришел на смену Ingress. Понять разделение ролей, научиться настраивать `GatewayClass`, `Gateway` и `HTTPRoute`, а также реализовывать продвинутые сценарии (traffic splitting).

---

## Предварительные требования

Для работы необходим установленный контроллер Gateway API. В нашем стенде мы используем **Envoy Gateway** в конфигурации NodePort.

Выполните скрипт инициализации:
```bash
export KUBECONFIG=/root/.kube/kubespray.conf
bash ../../scripts/bootstrap/11-install-gateway-api.sh
```
> Скрипт установит Gateway API CRDs (v1), Envoy Gateway Controller и создаст базовый `GatewayClass` с именем `eg`.

### Стартовая проверка

Убедитесь, что контроллер работает и кластер поддерживает новые ресурсы:
```bash
kubectl get gatewayclasses
# NAME   CONTROLLER                                      ACCEPTED   AGE
# eg     gateway.envoyproxy.io/gatewayclass-controller   True       ...
```

---

## Часть 1: Введение и отличие от Ingress

### Зачем нужен Gateway API?
Стандартный ресурс `Ingress` (появившийся в k8s 1.1) заархивирован: он больше не получает новых функций. Ingress имел ряд архитектурных недостатков:
1. **Слабая переносимость:** почти все продвинутые функции (rewrite, rate-limit, auth) настраивались через нестандартные `annotations` (например, `nginx.ingress.kubernetes.io/rewrite-target`).
2. **Отсутствие разделения ролей:** разработчик приложения (настраивающий пути) и администратор (настраивающий TLS и порты) редактировали один и тот же манифест `Ingress`.
3. **Бедность возможностей:** Ingress изначально не поддерживал разделение трафика (traffic splitting), TCP/UDP маршрутизацию, заголовки и gRPC.

### Как работает Gateway API
Новый стандарт разделяет конфигурацию на 3 независимых ресурса, отражающих роли в компании:
1. **GatewayClass** (Роль: Провайдер инфраструктуры). Описывает тип балансировщика (например, AWS ALB, NGINX, Envoy).
2. **Gateway** (Роль: Кластерный администратор). Точка входа трафика в кластер. Указывает, какие порты слушать и какие TLS-сертификаты использовать.
3. **HTTPRoute / TLSRoute / TCPRoute** (Роль: Разработчик приложения). Описывает конкретные правила маршрутизации (пути, заголовки) для сервиса.

**Сравнение:**
| Характеристика | Ingress | Gateway API |
|----------------|---------|-------------|
| Роли | Смешаны (1 ресурс) | Разделены (3 ресурса) |
| Маршрутизация по заголовкам | Только через аннотации | Встроено (`matches.headers`) |
| Разделение трафика (Canary) | Только через аннотации | Встроено (`backendRefs.weight`) |
| Протоколы | Только HTTP/HTTPS | HTTP, TCP, UDP, gRPC, TLS |

---

## Часть 2: Базовый роутинг (HTTPRoute)

Мы создадим простой сценарий:
- Namespace `lab-gateway`
- `Gateway` (слушает порт 80)
- Deployment/Service `store-v1`
- `HTTPRoute`, направляющий трафик с пути `/store` на сервис `store-v1`

### 2.1 Развертывание

```bash
kubectl apply -f manifests/01-basic-routing/app.yaml
kubectl apply -f manifests/01-basic-routing/gateway.yaml
kubectl apply -f manifests/01-basic-routing/httproute.yaml
```

**Разберем `gateway.yaml`:**
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: demo-gateway
  namespace: lab-gateway
spec:
  gatewayClassName: eg    # Связь с инфраструктурным провайдером
  listeners:
  - name: http
    protocol: HTTP
    port: 80              # Слушать на порту 80
```

**Разберем `httproute.yaml`:**
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: store-route
  namespace: lab-gateway
spec:
  parentRefs:
  - name: demo-gateway    # К какому шлюзу привязан маршрут
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /store
    backendRefs:
    - name: store-v1
      port: 80
```

### 2.2 Проверка

Подождите, пока Gateway получит статус `Programmed: True` (может занять до минуты):
```bash
kubectl wait --timeout=2m -n lab-gateway gateway/demo-gateway --for=condition=Programmed
kubectl get gateway -n lab-gateway
```

Теперь проверим маршрутизацию. Envoy Gateway в нашем стенде использует `NodePort`. Узнаем порт и сделаем запрос:
```bash
NODE_PORT=$(kubectl get svc -n envoy-gateway-system envoy-lab-gateway-demo-gateway-e5c9226f -o jsonpath='{.spec.ports[0].nodePort}')
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

curl -s http://$NODE_IP:$NODE_PORT/store
# Вывод: Store V1
```

---

## Часть 3: Traffic Splitting (Canary Releases)

Gateway API нативно поддерживает разделение трафика между разными версиями (или сервисами) с помощью весов (`weights`).

### 3.1 Запуск второй версии

Применим приложение `store-v2` и обновим `HTTPRoute`:
```bash
kubectl apply -f manifests/02-traffic-splitting/app-v2.yaml
kubectl apply -f manifests/02-traffic-splitting/httproute-split.yaml
```

В новом манифесте `httproute-split.yaml` мы добавили веса (90% на v1, 10% на v2):
```yaml
    backendRefs:
    - name: store-v1
      port: 80
      weight: 90
    - name: store-v2
      port: 80
      weight: 10
```

### 3.2 Проверка разделения

Сделаем 10 запросов. Ожидаем, что примерно 1 из 10 вернет `Store V2`:
```bash
for i in {1..10}; do curl -s http://$NODE_IP:$NODE_PORT/store; echo; done
```
> *Примечание:* Веса обрабатываются вероятностно, поэтому точное соотношение 9 к 1 будет видно на больших объемах трафика.

---

## Часть 4: TLS и интеграция с cert-manager

Как и `Ingress`, Gateway API поддерживает автоматический заказ TLS-сертификатов через `cert-manager`.

Разница в том, что `cert-manager` отслеживает ресурсы `Gateway` или `HTTPRoute`. Аннотации переехали на `Gateway`. Пример конфигурации TLS (манифест предоставлен для ознакомления в `manifests/03-tls-cert-manager/gateway-tls.yaml`):

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: demo-gateway-tls
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  gatewayClassName: eg
  listeners:
  - name: https
    protocol: HTTPS
    port: 443
    hostname: "api.example.com"
    tls:
      mode: Terminate
      certificateRefs:
      - name: api-example-com-tls   # Сюда cert-manager положит сертификат
```
*В рамках данного стенда (без реального домена) мы не будем разворачивать этот манифест, но его структура показывает, как элегантно TLS изолирован от разработчиков (HTTPRoute).*

---

## Проверка модуля

Выполните скрипт автопроверки (он убедится, что HTTPRoute работает и настроен traffic splitting):
```bash
bash verify/verify.sh
```

---

## Финальная карта ресурсов модуля

| Ресурс | Тип | Роль (Persona) | Что делает |
|--------|-----|----------------|------------|
| `eg` | `GatewayClass` | Инфраструктура | Определяет контроллер (Envoy) |
| `demo-gateway` | `Gateway` | Админ кластера | Слушает порт 80, принимает трафик |
| `store-route` | `HTTPRoute` | Разработчик | Направляет путь `/store` в сервисы с весами 90/10 |

---

## Теоретические вопросы (итоговые)

1. Какие три уровня ресурсов предлагает Gateway API и как они разделяют ответственность между командами?
2. В чем главное архитектурное преимущество Gateway API перед Ingress (помимо богатства функций)?
3. Как в Gateway API реализуется Canary-релиз (traffic splitting) без использования аннотаций?
4. Могут ли несколько `HTTPRoute` от разных команд ссылаться на один и тот же `Gateway`? (Подсказка: да, это основная фича дизайна).

---

## Практические задания (отработка)

> Проверяйте конфигурации на живом кластере.

1. Измените веса в `httproute-split.yaml` на 50/50, примените манифест и проверьте через цикл `curl`, что ответы чередуются равномерно.
2. Изучите вывод команды `kubectl describe httproute store-route -n lab-gateway` и найдите секцию `Status`. Обратите внимание на условие `Accepted: True`.
3. Опционально: создайте правило `HTTPRoute`, которое маршрутизирует трафик только при наличии определенного HTTP-заголовка (поиск в документации по `matches.headers`).

---

## Шпаргалка

```bash
# Просмотр основных ресурсов Gateway API
kubectl get gatewayclasses
kubectl get gateways -A
kubectl get httproutes -A

# Диагностика (ошибки привязки route к gateway будут здесь)
kubectl describe gateway <gateway-name>
kubectl describe httproute <route-name>
```

---

## Чему вы научились

В этом модуле вы научились:
- Различать зоны ответственности ресурсов Gateway API (GatewayClass, Gateway, HTTPRoute)
- Настраивать входящий трафик с использованием современного стандарта
- Осуществлять разделение трафика (Traffic Splitting) для Canary-релизов

---

## Уборка

Очистите ресурсы после завершения работы:
```bash
../../scripts/clean/clean-module.sh modules/23-gateway-api
```
*(Контроллер Envoy Gateway останется в кластере для будущих модулей).*
