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

## Уборка

Очистите ресурсы после завершения:
```bash
../../scripts/clean/clean-module.sh modules/18-logs-tracing
```
