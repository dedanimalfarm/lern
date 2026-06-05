# Лабораторная работа 18: Централизованное логирование (Loki + Promtail)
> ⏱ время ~25 мин · сложность 3/5 · пререквизиты: Трек 1 и Трек 2

В этом модуле мы развернём стек логирования Grafana Loki и агент сбора логов Promtail. Мы научимся собирать логи со всех подов кластера и искать их через единый интерфейс.

## Предварительные требования

```bash
export KUBECONFIG=/root/.kube/kubespray.conf
```

## Стартовая проверка

Убедитесь, что кластер доступен:
```bash
kubectl get nodes
```

## 1. Развёртывание Loki и Promtail

Разверните все ресурсы:
```bash
kubectl apply -f manifests/loki.yaml
kubectl apply -f manifests/promtail.yaml
kubectl apply -f manifests/app.yaml
kubectl apply -f manifests/datasource.yaml
```

Проверьте статус подов:
```bash
kubectl -n lab get pods
```

## 2. Изучение архитектуры

- **Loki** — серверная часть. Хранит индексы (labels) и сжатые чанки (chunks) логов. Мы используем монолитный режим для экономии ресурсов.
- **Promtail** — агент (DaemonSet), который работает на каждой ноде, читает логи контейнеров (`/var/log/pods`), прикрепляет к ним лейблы Kubernetes и отправляет в Loki.

## Практические задания

### Задание 1. Запрос логов напрямую
Хотя обычно логи ищут через Grafana Explore, вы можете опросить Loki API напрямую:
```bash
kubectl -n lab exec deploy/loki -- wget -qO- 'http://localhost:3100/loki/api/v1/query?query={app="log-generator"}'
```

### Задание 2. Интеграция с Grafana
Если в вашем кластере установлена Grafana (например, из модуля 17), Loki будет автоматически подключён как Datasource, так как мы создали Secret `loki-datasource` с лейблом `grafana_datasource: "1"`.

Зайдите в Grafana -> Explore -> Выберите источник Loki и выполните запрос:
```logql
{namespace="lab", app="log-generator"}
```

---

## Архитектура: Loki + Promtail

```text
┌─────────────────┐       ┌─────────────┐       ┌─────────────────┐
│  Pod (app: A)   │       │             │       │   Grafana UI    │
│  stdout / logs  ├──────►│  Promtail   │       │ (LogQL queries) │
└─────────────────┘       │ (DaemonSet) │       └─────────┬───────┘
                          │             │                 │
┌─────────────────┐       │ - читает    │       ┌─────────▼───────┐
│  Pod (app: B)   ├──────►│   /var/log  ├──────►│   Loki Server   │
│  stdout / logs  │       │ - парсит    │ (HTTP)│  (StatefulSet/  │
└─────────────────┘       │   labels    │       │   Deployment)   │
                          └─────────────┘       └─────────────────┘
```

**Особенности Loki (в отличие от ELK):**
- **Не индексирует текст.** Индексируются ТОЛЬКО лейблы (как в Prometheus).
- Сам текст логов сжимается в "чанки" (chunks) и хранится в объектном или локальном хранилище.
- Это делает Loki очень экономным по ресурсам (RAM/CPU), но полнотекстовый поиск реализован полным перебором (brute-force) внутри чанков, отфильтрованных по лейблам.

---

## Финальная карта ресурсов модуля

| Ресурс | Тип | Роль |
|--------|-----|------|
| `loki` | Deployment / Service | Центральный сервер хранения логов и обработки запросов |
| `loki` | ConfigMap | Конфигурация Loki (storage, limits, schema) |
| `promtail` | DaemonSet | Агент сбора логов, запущенный на каждой ноде кластера |
| `promtail` | ConfigMap | Конфигурация сбора (scrape_configs, пути `/var/log/pods`) |
| `promtail` | ClusterRoleBinding | Права на чтение Pods/Namespaces для получения метаданных (лейблов) |
| `log-generator` | Deployment | Тестовое приложение, генерирующее случайные логи |

---

## Теоретические вопросы (итоговые)

1. Чем архитектура Loki принципиально отличается от Elasticsearch/OpenSearch с точки зрения индексации?
2. Почему Promtail разворачивается как DaemonSet, а не как обычный Deployment?
3. Какие каталоги на ноде (hostPath) должен монтировать Promtail для успешного сбора логов?
4. Что такое "кардинальность лейблов" (label cardinality) и почему нельзя делать уникальный лейбл для каждого запроса (например, `request_id`)?


## Чему вы научились

В этом модуле вы научились:
- Развёртыванию стека логирования Loki + Promtail
- Работе с LogQL для запросов по логам
- Диагностике конфигурации агентов сбора логов

## Уборка

Очистите ресурсы после завершения:
```bash
../../scripts/clean/clean-module.sh modules/18-logs-tracing
```
