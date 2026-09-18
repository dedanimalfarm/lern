# Сценарий 02: ADDRESS есть, а ответ — 503

## Симптом

В отличие от сценария 01, Ingress подхвачен контроллером (`ADDRESS` заполнен), но трафик не доходит:

```bash
kubectl -n lab get ingress web-port
# NAME       CLASS   HOSTS            ADDRESS       PORTS   AGE
# web-port   nginx   port.lab.local   10.233.x.x    80      1m
kubectl -n lab run curl --rm -i --restart=Never --quiet --image=curlimages/curl:8.10.1 -- \
  curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: port.lab.local' http://ingress-nginx-controller.ingress-nginx/
# 503
```

## Запуск

```bash
kubectl -n lab apply -k manifests/
kubectl -n lab apply -f broken/scenario-02/ingress-port.yaml
sleep 5
```

## Задание

1. По дереву диагностики модуля определите класс проблемы по коду 503.
2. Найдите в логах/событиях контроллера, что именно не так с бэкендом.
3. Исправьте Ingress и получите 200.

Начните:

```bash
kubectl -n lab describe ingress web-port | grep -A3 'Rules'
kubectl -n lab get svc web-a -o jsonpath='{.spec.ports[*].port}{"\n"}'
kubectl -n ingress-nginx logs deploy/ingress-nginx-controller --tail=50 | grep -i 'web-port' | tail -3
```

<details>
<summary><strong>Подсказка 1</strong></summary>

503 от ingress-nginx = правило найдено, а upstream пуст: контроллер не нашёл endpoints для указанного порта Service.

</details>

<details>
<summary><strong>Подсказка 2</strong></summary>

В `describe ingress` бэкенд `web-a:8080 (<none>)` — у Service `web-a` порт только 80, порта 8080 нет, endpoints для него пусты.

</details>

<details>
<summary><strong>Объяснение</strong></summary>

- Ingress ссылается на `web-a` порт `8080`, а Service публикует только `80`. Контроллер
  строит upstream по endpoints **конкретного порта** — их нет → `503 Service Temporarily
  Unavailable`.
- Отличие от сценария 01: там Ingress не был взят контроллером (нет `ingressClassName`,
  ADDRESS пуст); здесь маршрутизация настроена, ошибка на последнем шаге.
- Быстрая проверка: `describe ingress` показывает `(<none>)` у бэкенда без endpoints.

</details>

<details>
<summary><strong>Решение</strong></summary>

Указать порт, который есть у Service — `solutions/scenario-02/ingress-port.yaml` (`80`):

```bash
kubectl -n lab apply -f solutions/scenario-02/ingress-port.yaml
kubectl -n lab run curl --rm -i --restart=Never --quiet --image=curlimages/curl:8.10.1 -- \
  curl -s -H 'Host: port.lab.local' http://ingress-nginx-controller.ingress-nginx/     # hello from web-a
kubectl -n lab delete ingress web-port      # уборка
```

</details>
