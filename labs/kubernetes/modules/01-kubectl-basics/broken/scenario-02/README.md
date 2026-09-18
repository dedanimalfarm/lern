# Сценарий 02: Pod Running, но Service пустой

## Симптом

Deployment `kb-web` поднят, под в `Running`, но сервис не отвечает:

```bash
kubectl -n lab get pods -l app=kb-web
# NAME                      READY   STATUS    RESTARTS   AGE
# kb-web-...                0/1     Running   0          40s     <- Running, но 0/1
kubectl -n lab get endpoints kb-web
# NAME     ENDPOINTS   AGE
# kb-web   <none>      40s                                         <- трафику некуда идти
```

## Запуск

```bash
kubectl -n lab apply -f manifests/app/svc.yaml
kubectl -n lab apply -f broken/scenario-02/deploy.yaml
kubectl -n lab get pods -l app=kb-web -w
```

## Задание

1. Объясните, почему под `Running`, а `READY` показывает `0/1`.
2. Найдите, какая именно проверка не проходит и почему.
3. Исправьте манифест и убедитесь, что в `endpoints` появился адрес пода.

Начните:

```bash
kubectl -n lab describe pod -l app=kb-web | tail -15
kubectl -n lab get deploy kb-web -o jsonpath='{.spec.template.spec.containers[0].readinessProbe}{"\n"}'
```

<details>
<summary><strong>Подсказка 1</strong></summary>

Колонка `READY` — это не «процесс жив», а «readinessProbe прошла». Смотрите `Events` в `describe pod`.

</details>

<details>
<summary><strong>Подсказка 2</strong></summary>

В событиях есть `Readiness probe failed: HTTP probe failed with statuscode: 404`. Какой путь запрашивает проба и есть ли он у nginx?

</details>

<details>
<summary><strong>Объяснение</strong></summary>

- readinessProbe стучится в `/healthz-typo`, nginx отдаёт 404 → проба не проходит.
- Под не становится Ready, а Service кладёт в Endpoints **только** Ready-поды — поэтому
  список пуст и трафик не идёт, хотя контейнер работает.
- Это не ошибка приложения, а расхождение между манифестом и тем, что приложение
  умеет отдавать.

</details>

<details>
<summary><strong>Решение</strong></summary>

Вернуть пробе путь, который nginx действительно отдаёт (`/`).

```bash
kubectl -n lab apply -f solutions/scenario-02/deploy.yaml
kubectl -n lab rollout status deploy/kb-web --timeout=60s
kubectl -n lab get endpoints kb-web      # появился <ip>:80
```

</details>
