# Решение сценария 02

**Причина.** бэкенд Ingress указывает на порт 8080, которого нет у Service `web-a` (только 80) → upstream без endpoints → 503.

**Исправление.**
```bash
kubectl -n lab apply -f solutions/scenario-02/ingress-port.yaml
```

**Проверка.**
```bash
kubectl -n lab run curl --rm -i --restart=Never --quiet --image=curlimages/curl:8.10.1 -- curl -s -H 'Host: port.lab.local' http://ingress-nginx-controller.ingress-nginx/
```
