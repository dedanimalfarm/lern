# 02-egress-control

## Задача
Понять, почему egress-сторона так же важна, как ingress.

## Идея
- `default-deny` закрывает И egress. Без `allow-dns` ломается резолв имён.
- web ходит к api только потому, что у web есть egress-правило к api, а у api —
  ingress-правило от web. Нужны ОБЕ стороны.

## Проверка
```bash
# убрать web-egress -> web перестанет ходить даже к api (хотя api ingress разрешает)
kubectl -n lab delete netpol web-egress
kubectl -n lab run t --image=busybox:1.36 --restart=Never -i --rm -- wget -qO- --timeout=4 http://api
# вернуть
kubectl -n lab apply -f manifests/netpol/02-web.yaml
```
