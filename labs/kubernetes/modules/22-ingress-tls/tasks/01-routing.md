# 01 — L7 маршрутизация (host и path)

## Задача
Развернуть web-a/web-b и развести трафик: host a.lab.local→web-a, b.lab.local→web-b;
path paths.lab.local/a→web-a, /b→web-b (с rewrite-target).

## Проверка
```bash
kubectl -n lab apply -f manifests/apps.yaml -f manifests/ingress.yaml
CIP=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.spec.clusterIP}')
kubectl -n lab run c --image=curlimages/curl:8.10.1 --restart=Never -i --rm -- \
  curl -s --resolve a.lab.local:80:$CIP http://a.lab.local/   # hello from web-a
```
