# Сценарий 02: Скрытое исчерпание квоты (ResourceQuota)

## Симптом

Вы успешно применили Deployment, команда `kubectl apply` отработала без ошибок и написала `deployment.apps/quota-demo created`. 
Однако, когда вы проверяете поды — их нет, или запустился только один из двух запрошенных.

## Запуск

```bash
kubectl -n lab apply -f quota.yaml
kubectl -n lab apply -f deploy.yaml
kubectl -n lab get pods -l app=quota-demo
```

## Задание

1. Найдите, какой объект в Kubernetes отвечает за создание Pod'ов от имени Deployment.
2. Проверьте события этого объекта, чтобы узнать, почему он не может создать нужное количество реплик.
3. Исправьте конфигурацию ресурсов в Deployment, чтобы он вписался в ограничения.

Начните:

```bash
kubectl -n lab get deploy quota-demo
kubectl -n lab get rs -l app=quota-demo
kubectl -n lab describe rs -l app=quota-demo
```

<details>
<summary><strong>Подсказка 1</strong></summary>

Сам Deployment не создает Pod'ы напрямую. Он создает объект `ReplicaSet`, который управляет Pod'ами.
Поскольку Deployment валиден, он создается успешно. Но ReplicaSet может столкнуться с ошибкой при попытке запросить API Kubernetes на создание Pod'а.

</details>

<details>
<summary><strong>Подсказка 2</strong></summary>

Вывод `describe rs` в секции Events показывает ошибку `Forbidden: exceeded quota: demo-quota, requested: requests.cpu=600m, used: requests.cpu=..., limited: requests.cpu=1`.

Посмотрим на квоту в namespace:
```bash
kubectl -n lab describe quota demo-quota
```
Вы увидите, что `requests.cpu` ограничен 1 ядром (`1` или `1000m`).

</details>

<details>
<summary><strong>Объяснение</strong></summary>

- Наш Deployment просит 2 реплики.
- Каждый контейнер запрашивает `requests.cpu: 600m`.
- Суммарный запрос: 2 * 600m = 1200m (1.2 CPU).
- Это превышает лимит в 1 CPU, установленный в `ResourceQuota`.
- Admission Controller Kubernetes блокирует создание второго Pod'а (или обоих, в зависимости от того, что уже было запущено).

</details>

<details>
<summary><strong>Решение</strong></summary>

Необходимо снизить аппетиты приложения, если это возможно, либо запросить увеличение квоты.
В рамках сценария, снизим `requests.cpu` контейнера с 600m до 200m:

```bash
kubectl -n lab apply -f ../../solutions/02-quota-exceeded/deploy.yaml
kubectl -n lab get pods -l app=quota-demo
```

Теперь суммарный запрос будет 2 * 200m = 400m, что легко вписывается в квоту.

</details>
