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
