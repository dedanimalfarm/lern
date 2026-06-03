# 02 — TLS termination (вручную)

## Задача
Сгенерировать self-signed cert на secure.lab.local, положить в Secret
kubernetes.io/tls, включить HTTPS через spec.tls в Ingress.

## Проверка
```bash
openssl req -x509 -nodes -newkey rsa:2048 -days 365 -keyout /tmp/s.key -out /tmp/s.crt \
  -subj "/CN=secure.lab.local" -addext "subjectAltName=DNS:secure.lab.local"
kubectl -n lab create secret tls secure-tls --cert=/tmp/s.crt --key=/tmp/s.key
kubectl -n lab apply -f manifests/tls/ingress-tls.yaml
# curl -skv --resolve secure.lab.local:443:$CIP https://secure.lab.local/ -> subject CN=secure.lab.local
```
