# Сценарий 01: Под внутри vcluster вечно Pending (host-квота)

## Симптом

Внутри виртуального кластера создан Pod. Ошибок при `apply` не было, нод
достаточно, но Pod навсегда завис в `Pending`. В host-кластере под при этом
вообще не появился.

## Запуск

```bash
# kubeconfig виртуального кластера + порт-форвард (если ещё не сделано)
kubectl get secret vc-my-vcluster -n lab -o jsonpath='{.data.config}' | base64 -d \
  | sed 's|server: https://.*|server: https://localhost:18443|' > vcluster.yaml
kubectl -n lab port-forward svc/my-vcluster 18443:443 &

kubectl --kubeconfig vcluster.yaml apply -f pod.yaml
kubectl --kubeconfig vcluster.yaml get pod greedy-app -w
```

## Задание

1. Выясните, почему Pod не планируется, хотя внутри vcluster нет ни квот, ни лимитов.
2. Найдите, на каком уровне (виртуальном или хостовом) возникает отказ.
3. Исправьте манифест так, чтобы Pod запустился.

Начните:

```bash
kubectl --kubeconfig vcluster.yaml describe pod greedy-app
kubectl --kubeconfig vcluster.yaml get events --field-selector involvedObject.name=greedy-app
```

<details>
<summary><strong>Подсказка 1</strong></summary>

В `describe pod` внутри vcluster секция Events может быть пустой — обычных
событий планировщика (`FailedScheduling`) НЕТ, потому что до планировщика дело
не дошло. Зато `get events` показывает событие от syncer'а (снято с этого
кластера):

```
Warning  SyncError  pod/greedy-app
  Error syncing to host cluster: create object:
  pods "greedy-app-x-default-x-my-vcluster" is forbidden:
  exceeded quota: lab-quota, requested: limits.cpu=1500m,
  used: limits.cpu=1500m, limited: limits.cpu=2
```

</details>

<details>
<summary><strong>Подсказка 2</strong></summary>

У vcluster нет своих нод: его syncer создаёт «теневую» копию каждого пода в
host-namespace (`lab`). А в `lab` действует ResourceQuota хост-кластера:

```bash
# на ХОСТЕ (без --kubeconfig)
kubectl -n lab describe quota lab-quota
```

Сам vcluster (limits.cpu=1) и его CoreDNS (200m) уже забронировали часть квоты.
Запрошенные подом `limits.cpu: 1500m` в остаток не помещаются.

</details>

<details>
<summary><strong>Объяснение</strong></summary>

- vcluster — это «контрольная плоскость напрокат»: внутри свой API-сервер без
  квот и админских ограничений, но РАБОТАЮТ поды всё равно в host-namespace.
- Все контракты host-кластера (ResourceQuota, LimitRange, PSA, NetworkPolicy)
  продолжают действовать на синхронизированные поды.
- Отказ возникает при создании host-копии (admission хоста), поэтому внутри
  vcluster он виден только как `SyncError`-событие, а под остаётся `Pending`.
- Это и есть главный урок hard multi-tenancy: тенант получает СВОЙ API, но не
  больше РЕСУРСОВ, чем выделил ему оператор платформы.

</details>

<details>
<summary><strong>Решение</strong></summary>

Уменьшить запросы/лимиты пода до остатка квоты (или попросить оператора
платформы расширить квоту namespace'а):

```bash
kubectl --kubeconfig vcluster.yaml delete pod greedy-app
kubectl --kubeconfig vcluster.yaml apply -f ../../solutions/01-host-quota/pod.yaml
kubectl --kubeconfig vcluster.yaml get pod greedy-app
# NAME         READY   STATUS    RESTARTS   AGE
# greedy-app   1/1     Running   0          20s

# и в host появился его двойник:
kubectl -n lab get pod greedy-app-x-default-x-my-vcluster
```

</details>
