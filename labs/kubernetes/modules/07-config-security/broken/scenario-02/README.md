# Сценарий 02: Ошибка авторизации (RBAC)

## Симптом

Deployment `api-client` (HTTP-клиент, который ходит в Kubernetes API с токеном своего ServiceAccount'а) постоянно перезапускается и уходит в `CrashLoopBackOff`. В логах Pod'а видно, что API отвечает на запрос списка ConfigMap'ов ошибкой `403`.

## Запуск

```bash
kubectl -n lab apply -f rbac.yaml
kubectl -n lab apply -f deploy.yaml
kubectl -n lab get pods -l app=api-client -w
```

## Задание

1. Выясните причину сбоя Pod'а, прочитав его логи.
2. Проверьте манифесты RBAC (`Role` и `ServiceAccount`), которые используются этим Pod'ом.
3. Найдите отсутствующее звено в цепочке авторизации и восстановите работу приложения.

Начните:

```bash
kubectl -n lab logs -l app=api-client --tail=20
kubectl -n lab get role configmap-reader -o yaml
kubectl -n lab get sa api-reader
```

<details>
<summary><strong>Подсказка 1</strong></summary>

В логах вы увидите (снято с этого кластера):

```
Attempting to list configmaps via API...
API answered: HTTP 403
Failed to list configmaps. Exiting.
```

403 Forbidden — это ошибка АВТОРИЗАЦИИ (authorization), а не аутентификации: API-сервер опознал субъекта (`system:serviceaccount:lab:api-reader` — токен валиден), но RBAC не разрешает ему verb `list` на ресурсе `configmaps`. Проверить можно и без пода:

```bash
kubectl -n lab auth can-i list configmaps --as=system:serviceaccount:lab:api-reader
```

</details>

<details>
<summary><strong>Как клиент авторизуется в API (контекст)</strong></summary>

kubelet монтирует в под projected-токен ServiceAccount'а в
`/var/run/secrets/kubernetes.io/serviceaccount/` (token + ca.crt + namespace).
Наш клиент — обычный `curl`, который передаёт его в заголовке:

```
curl --cacert $SA_DIR/ca.crt -H "Authorization: Bearer $(cat $SA_DIR/token)" \
  https://kubernetes.default.svc/api/v1/namespaces/lab/configmaps
```

`GET .../configmaps` (коллекция) с точки зрения RBAC — это verb `list`.

</details>

<details>
<summary><strong>Подсказка 2</strong></summary>

Вы проверили `Role` по имени `configmap-reader`. Она содержит нужные права: `get` и `list` для `configmaps`.
Вы проверили `ServiceAccount` — он тоже существует.

Как связать `Role` (набор прав) и `ServiceAccount` (субъект), чтобы права начали действовать?

</details>

<details>
<summary><strong>Объяснение</strong></summary>

- В `rbac.yaml` созданы `ServiceAccount` и `Role`.
- Однако они никак не связаны друг с другом!
- В Kubernetes для назначения `Role` конкретному пользователю или `ServiceAccount` необходимо создать объект `RoleBinding`.
- Без `RoleBinding` приложение имеет только базовые права по умолчанию (которые не включают чтение ConfigMap).

</details>

<details>
<summary><strong>Решение</strong></summary>

Добавьте объект `RoleBinding`, который свяжет `ServiceAccount` `api-reader` с `Role` `configmap-reader`.

```bash
kubectl -n lab apply -f ../../solutions/02-rbac-forbidden/rbac.yaml
kubectl -n lab logs -l app=api-client -f
```

Права применяются на лету — пересоздавать под не обязательно, он сам
перезапустится по backoff'у. В логах появится:

```
Attempting to list configmaps via API...
API answered: HTTP 200
Success! Sleeping 60s...
```

</details>
