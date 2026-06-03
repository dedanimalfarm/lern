# 01 — QoS-классы

## Задача
Развернуть три пода и убедиться, что k8s присвоил им QoS Guaranteed / Burstable /
BestEffort по их requests/limits.

## Проверка
```bash
kubectl -n lab apply -f manifests/qos.yaml
for p in qos-guaranteed qos-burstable qos-besteffort; do
  kubectl -n lab get pod $p -o jsonpath="$p={.status.qosClass}{'\n'}"; done
```
