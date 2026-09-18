# 03-operator-pattern

## Задача
Понять, что такое оператор, на РЕАЛЬНОМ примере.

## Идея
- CRD без контроллера — просто «запись в базе». Чтобы CR что-то ДЕЛАЛ, нужен
  контроллер (reconcile loop), который смотрит CR и приводит кластер к нему.
- Связка CRD + контроллер = **оператор**.

## Реальный пример на кластере: prometheus-operator
```bash
# CRD, которыми управляет prometheus-operator (модуль 17):
kubectl get crd | grep monitoring.coreos.com
# prometheuses, servicemonitors, prometheusrules, alertmanagers ...

# Когда вы создаёте ServiceMonitor (CR), оператor (контроллер) ПЕРЕНАСТРАИВАЕТ
# Prometheus — это и есть reconcile в действии.
kubectl -n monitoring get pods | grep operator
```
## Проверка
```bash
kubectl -n monitoring get servicemonitor
kubectl -n monitoring get secret prometheus-kps-kube-prometheus-stack-prometheus -o jsonpath='{.data.prometheus\.yaml\.gz}' | base64 -d | gunzip | grep -c 'job_name'
kubectl -n lab apply -f - <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata: { name: operator-demo, namespace: lab, labels: { release: kps } }
spec:
  selector: { matchLabels: { app: operator-demo } }
  endpoints: [{ port: http, interval: 30s }]
EOF
sleep 30
kubectl -n monitoring get secret prometheus-kps-kube-prometheus-stack-prometheus -o jsonpath='{.data.prometheus\.yaml\.gz}' | base64 -d | gunzip | grep -c 'job_name'
```

## Ожидаемый результат
- После создания `ServiceMonitor/operator-demo` число `job_name` в сгенерированном конфиге
  Prometheus выросло на один — оператор заметил CR и пересобрал конфигурацию без вашего
  участия (таргетов у job нет: Service с меткой `app: operator-demo` не существует, и это
  неважно — конфиг перестраивается по факту появления CR).
- Уберите CR (`kubectl -n lab delete servicemonitor operator-demo`) — через ~30 с job исчез.
- Вы объяснили, что оператор наблюдает через watch, какие ресурсы он **владеет**
  (`ownerReferences` на Secret/StatefulSet) и что случится с конфигом, если удалить
  ServiceMonitor.
