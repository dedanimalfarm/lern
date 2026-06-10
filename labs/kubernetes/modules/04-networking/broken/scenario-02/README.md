# Сценарий 02: Несовпадение TargetPort

## Симптом

Deployment успешно работает, Pod'ы запущены. Service находит Pod'ы и `Endpoints` корректно заполнены. Однако при попытке сделать `curl` к Service соединение завершается с ошибкой `Connection refused`.

## Запуск

```bash
kubectl -n lab apply -f deploy.yaml
kubectl -n lab apply -f svc.yaml
kubectl -n lab get pods -l app=net-demo-port
```

## Задание

1. Убедитесь, что Pod'ы работают, а Service имеет список Endpoints.
2. Проверьте связность: создайте временный pod и попробуйте сделать запрос к сервису `net-demo-port`.
3. Найдите несоответствие в портах.
4. Исправьте конфигурацию Service и восстановите трафик.

Начните:

```bash
kubectl -n lab get svc net-demo-port
kubectl -n lab get endpoints net-demo-port
kubectl -n lab describe svc net-demo-port
kubectl -n lab get deploy net-demo-port -o yaml | grep -i port
```

<details>
<summary><strong>Подсказка 1</strong></summary>

Проверьте, имеет ли Service IP адреса в `Endpoints`:
```bash
kubectl -n lab get endpoints net-demo-port
```

Реальный вывод с этого кластера:

```
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME            ENDPOINTS                               AGE
net-demo-port   10.233.104.201:8080,10.233.111.9:8080   2s
```

(Warning безвреден: API Endpoints помечен устаревшим в пользу EndpointSlice,
но вывод корректен. Можно смотреть и `kubectl -n lab get endpointslices`.)

Да, адреса есть. Значит, selector настроен правильно. Присмотритесь к выводу внимательнее: на какой ПОРТ указывают endpoints и какой порт на самом деле слушает nginx в контейнере?

</details>

<details>
<summary><strong>Подсказка 2</strong></summary>

Если Service перенаправляет трафик на правильные Pod'ы, возможно, он отправляет его не на тот порт, который слушает приложение?

Посмотрите, на какой порт направляет трафик Service:
```bash
kubectl -n lab get svc net-demo-port -o jsonpath='{.spec.ports[0].targetPort}'
```

И какой порт реально слушает контейнер (nginx):
```bash
kubectl -n lab get deploy net-demo-port -o jsonpath='{.spec.template.spec.containers[0].ports[0].containerPort}'
```

</details>

<details>
<summary><strong>Объяснение</strong></summary>

- Приложение `nginx` слушает на порту `80` внутри контейнера.
- Service настроен перенаправлять трафик на `targetPort: 8080`.
- Когда трафик приходит на порт `8080` контейнера, там нет слушающего процесса (nginx слушает 80).
- Ядро сети внутри Pod'а отклоняет пакет с `Connection refused`.

</details>

<details>
<summary><strong>Решение</strong></summary>

Исправить `targetPort` в `svc.yaml` с `8080` на `80`.

```bash
kubectl -n lab apply -f ../../solutions/02-targetport-mismatch/svc.yaml
```

Для проверки создайте тестовый pod и отправьте запрос:
```bash
kubectl -n lab run curl-test --image=curlimages/curl --restart=Never --rm -it -- curl -m 5 -sI http://net-demo-port
```
</details>
