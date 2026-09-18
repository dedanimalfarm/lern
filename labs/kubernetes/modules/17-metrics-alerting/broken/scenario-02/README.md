# Сценарий 02: ServiceMonitor подхвачен, а таргета в Prometheus нет

## Симптом

Метка `release: kps` на месте (это не сценарий 01), Prometheus видит ServiceMonitor, но
в Status → Targets блок `serviceMonitor/lab/metrics-app-v2/0` пуст — `(0/0 up)`:

```bash
kubectl -n monitoring port-forward svc/kps-kube-prometheus-stack-prometheus 19090:9090 &
curl -s 'http://localhost:19090/api/v1/targets?state=active' | grep -c 'metrics-app-v2'
# 0
```

## Запуск

```bash
kubectl -n lab apply -k manifests/
kubectl -n lab apply -f broken/scenario-02/servicemonitor.yaml
sleep 60
```

## Задание

1. Разберитесь, чем «ServiceMonitor не выбран» отличается от «ServiceMonitor выбран, но endpoints нет».
2. Сверьте `spec.endpoints[].port` с портами Service `metrics-app`.
3. Исправьте и дождитесь таргета `UP`.

Начните:

```bash
kubectl -n lab get svc metrics-app -o jsonpath='{.spec.ports[*].name}{"\n"}'
kubectl -n lab get servicemonitor metrics-app-v2 -o jsonpath='{.spec.endpoints[*].port}{"\n"}'
```

<details>
<summary><strong>Подсказка 1</strong></summary>

`endpoints[].port` в ServiceMonitor — это **имя** порта Service, а не номер. У Service `metrics-app` порт называется `metrics`.

</details>

<details>
<summary><strong>Подсказка 2</strong></summary>

Prometheus строит job из ServiceMonitor, но relabel по имени порта не находит ни одного endpoint → job есть, таргетов ноль. В `/api/v1/targets?state=dropped` они видны как отброшенные.

</details>

<details>
<summary><strong>Объяснение</strong></summary>

- ServiceMonitor ссылается на порт `http`, а Service публикует порт `metrics`. Оператор
  сгенерировал scrape-job, но фильтр `__meta_kubernetes_endpoint_port_name == "http"`
  отбросил все endpoints.
- Симптом отличается от сценария 01 (там ServiceMonitor вообще не выбран из-за метки):
  здесь job существует, но пустой.
- Правило: имена портов в Service и ServiceMonitor — часть контракта; проверяйте
  `kubectl get svc -o jsonpath='{.spec.ports[*].name}'`.

</details>

<details>
<summary><strong>Решение</strong></summary>

Указать реальное имя порта — `solutions/scenario-02/servicemonitor.yaml` (`port: metrics`):

```bash
kubectl -n lab apply -f solutions/scenario-02/servicemonitor.yaml
sleep 60; curl -s 'http://localhost:19090/api/v1/targets?state=active' | grep -c 'metrics-app-v2'   # 1
kubectl -n lab delete servicemonitor metrics-app-v2      # уборка
```

</details>
