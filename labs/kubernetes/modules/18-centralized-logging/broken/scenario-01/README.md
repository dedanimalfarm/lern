# Сценарий 01: Логи не поступают в Loki

## Симптом

Приложение генерирует логи, поды Promtail работают (Running), однако в Grafana/Loki запросы `{namespace="lab"}` возвращают пустой результат.

## Предварительные требования

```bash
export KUBECONFIG=/root/.kube/kubespray.conf
```

## Стартовая проверка

Убедитесь, что кластер доступен:
```bash
kubectl get nodes
```

## Запуск

```bash
kubectl apply -k broken/scenario-01
```
Подождите минуту, чтобы поды запустились.

## Задание

1. Посмотрите логи агента сбора логов (Promtail).
2. Найдите причину, по которой логи не отправляются.
3. Исправьте конфигурацию Promtail.

Начните диагностику:
```bash
kubectl -n lab logs -l app=promtail --tail=20
```

<details>
<summary><strong>Подсказка</strong></summary>

В логах Promtail вы должны увидеть ошибки `connection refused` или `no such host`. Обратите внимание на URL, к которому пытается подключиться Promtail (он берётся из конфигурации `clients.url`).
</details>

<details>
<summary><strong>Объяснение</strong></summary>

Promtail настроен на отправку логов по адресу `http://loki.default.svc.cluster.local:3100`, но Loki развёрнут в namespace `lab`. Из-за неверного DNS-имени Promtail не может найти сервер и выбрасывает логи или буферизует их с ошибкой.
</details>

<details>
<summary><strong>Решение</strong></summary>

Отредактируйте ConfigMap `promtail-config` или примените исправленный манифест:
```bash
kubectl apply -f manifests/promtail.yaml
```
Удалите поды Promtail, чтобы они перезапустились с новым конфигом:
```bash
kubectl -n lab delete pods -l app=promtail
```
</details>

## Уборка

Очистите ресурсы после завершения:
```bash
../../scripts/clean/clean-module.sh modules/18-centralized-logging
```
