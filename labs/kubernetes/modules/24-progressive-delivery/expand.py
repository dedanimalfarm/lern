import re

with open('/root/lern/labs/kubernetes/modules/24-progressive-delivery/README.md', 'r') as f:
    content = f.read()

addition = """

## Часть 7: Интеграция с Ingress и Service Mesh (Traffic Routing)

### Теория для изучения перед частью

Как мы обсуждали в первой части, базовый Canary (Basic Canary) использует масштабирование `ReplicaSet` для управления весом трафика. Если у нас 4 реплики, то минимальный шаг для разделения трафика — 25%. Что делать, если мы хотим запустить канарейку всего на 1% или 5% пользователей? А если мы хотим пускать на превью-версию только тестировщиков, у которых в браузере установлена специальная cookie или передан заголовок `X-Tester: true`?

В таких случаях Argo Rollouts предоставляет функционал **Traffic Routing** (маршрутизация трафика). Он интегрируется с различными ingress-контроллерами и service mesh, среди которых:
- **NGINX Ingress Controller**
- **ALB (AWS Load Balancer Controller)**
- **Istio**
- **Linkerd**
- **Gateway API (современный стандарт Kubernetes)**

### 7.1 Интеграция с NGINX Ingress

Для настройки интеграции с NGINX, вам необходимо создать Ingress-ресурс и сослаться на него в конфигурации Rollout.

**Пример архитектуры маршрутизации с NGINX:**
1. Вы создаете Ingress для вашего стабильного (stable) сервиса.
2. Argo Rollouts автоматически создает копию этого Ingress, добавляя к нему аннотацию `nginx.ingress.kubernetes.io/canary: "true"` и задавая нужный вес (`nginx.ingress.kubernetes.io/canary-weight`).
3. При каждом шаге (`setWeight`) контроллер обновляет значение веса в аннотации. NGINX Ingress Controller видит изменение аннотаций и динамически перестраивает конфигурацию (reload).

**Пример фрагмента манифеста Rollout для NGINX:**
```yaml
  strategy:
    canary:
      canaryService: rollout-canary
      stableService: rollout-stable
      trafficRouting:
        nginx:
          stableIngress: rollout-ingress
          additionalIngressAnnotations:   # Опционально: кастомные аннотации
            canary-by-header: X-Canary
      steps:
      - setWeight: 5
      - pause: {duration: 10m}
      - setWeight: 20
```

> **Важно:** При таком подходе количество реплик канарейки (`ReplicaSet`) больше не привязано к проценту трафика. Rollout может запустить всего 1 новый под, и направить на него ровно 5% трафика через Ingress, не запуская при этом 19 старых подов. Это существенно экономит ресурсы.

### 7.2 Интеграция с Istio Service Mesh

Если вы используете Service Mesh (например, Istio), Argo Rollouts управляет объектами `VirtualService` и `DestinationRule`.

**Пример архитектуры с Istio:**
1. Вы создаете `VirtualService` с маршрутизацией по умолчанию на `stable` подмножество (subset).
2. Вы указываете этот `VirtualService` в манифесте Rollout.
3. При выполнении шагов `setWeight`, Rollouts динамически обновляет веса в `VirtualService` (секция `route[].weight`). Истинная балансировка происходит на уровне Envoy-прокси (sidecar) в подах.

**Пример фрагмента Rollout для Istio:**
```yaml
  strategy:
    canary:
      canaryService: rollout-canary
      stableService: rollout-stable
      trafficRouting:
        istio:
          virtualService:
            name: rollout-vsvc
            routes:
            - primary
      steps:
      - setWeight: 1
      - pause: {duration: 5m}
      - setWeight: 10
```

### 7.3 Header-based Routing (Маршрутизация по заголовкам)

Самая мощная функция Traffic Routing — это возможность полностью исключить новую версию из публичного доступа, но при этом дать к ней доступ тестировщикам.

Вместо `setWeight`, вы можете использовать `setHeaderRoute`:
```yaml
      steps:
      - setCanaryScale:
          weight: 25  # Поднимаем 25% подов, но не даем им вес трафика
      - setHeaderRoute:
          match:
            - headerName: X-Tester
              headerValue:
                exact: "true"
      - pause: {}     # QA тестируют, передавая заголовок
      - setWeight: 50 # Если QA довольны, пускаем реальных юзеров
```
При такой настройке обычные пользователи получат только старую версию, а любой HTTP запрос с заголовком `X-Tester: true` будет гарантированно направлен на канарейку.

### 7.4 Gateway API

Современным стандартом вместо Ingress становится Kubernetes Gateway API (`HTTPRoute`, `Gateway` и др.). Argo Rollouts поддерживает его нативно. Вместо Ingress вы указываете `HTTPRoute`, и Rollouts меняет веса непосредственно в правилах `backendRefs`.

**Контрольные вопросы к Части 7:**
1. Почему Traffic Routing позволяет обойти ограничение минимального шага в 25% при 4 репликах?
2. Какие ресурсы Kubernetes изменяет Argo Rollouts для управления трафиком в NGINX Ingress? А какие в Istio?
3. В каких сценариях `setHeaderRoute` предпочтительнее процентного `setWeight`?

"""

content = content.replace("## Часть 6: Troubleshooting — боевые инциденты", addition + "## Часть 6: Troubleshooting — боевые инциденты")

# Also let's update the TOC
toc_addition = """- [Часть 7: Интеграция с Ingress и Service Mesh (Traffic Routing)](#часть-7-интеграция-с-ingress-и-service-mesh-traffic-routing)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-7)
  - [7.1 Интеграция с NGINX Ingress](#71-интеграция-с-nginx-ingress)
  - [7.2 Интеграция с Istio Service Mesh](#72-интеграция-с-istio-service-mesh)
  - [7.3 Header-based Routing (Маршрутизация по заголовкам)](#73-header-based-routing-маршрутизация-по-заголовкам)
  - [7.4 Gateway API](#74-gateway-api)
"""

content = content.replace("- [Часть 6: Troubleshooting — боевые инциденты]", toc_addition + "- [Часть 6: Troubleshooting — боевые инциденты]")

with open('/root/lern/labs/kubernetes/modules/24-progressive-delivery/README.md', 'w') as f:
    f.write(content)
