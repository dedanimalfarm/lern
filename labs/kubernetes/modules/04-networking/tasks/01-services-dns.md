# 01-services-dns

## Задача
Развернуть приложение и проверить DNS-resolve сервиса из debug pod.

## Команды
```bash
kubectl -n lab apply -f manifests/services
kubectl -n lab run dnscheck --image=busybox:1.36 --restart=Never -- nslookup net-demo.lab.svc.cluster.local
```
## Ожидаемый результат
- `nslookup` вернул ClusterIP сервиса `net-demo` из Service-сети стенда (`10.233.0.0/18`),
  сервер DNS — nodelocaldns `169.254.25.10`.
- `kubectl -n lab get endpointslices -l kubernetes.io/service-name=net-demo` показывает
  IP подов; без Ready-подов список пуст, а имя всё равно резолвится.
- Вы объяснили разницу между `net-demo`, `net-demo.lab` и `net-demo.lab.svc.cluster.local`
  и откуда берутся `search`-домены в `/etc/resolv.conf` пода.
