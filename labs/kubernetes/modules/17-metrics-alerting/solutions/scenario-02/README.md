# Решение сценария 02

**Причина.** `spec.endpoints[].port: http` не совпадает с именем порта `metrics` у Service → job создан, endpoints отброшены relabel'ом, таргетов нет.

**Исправление.**
```bash
kubectl -n lab apply -f solutions/scenario-02/servicemonitor.yaml
```

**Проверка.**
```bash
curl -s 'http://localhost:19090/api/v1/targets?state=active' | grep -c metrics-app-v2   # 1
```
