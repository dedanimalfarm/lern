# Сценарий 02: RWO-том и replicas > 1 (вечный Pending / Multi-Attach)

## Симптом

Один Pod из Deployment успешно запустился и работает, а второй навсегда застрял
в статусе `Pending` — scheduler не может найти для него ни одной подходящей ноды.

> На облачных кластерах с CSI-драйвером блочных дисков (EBS, GCP PD) та же
> ошибка конфигурации проявляется иначе: второй Pod зависает в
> `ContainerCreating` с событием `Multi-Attach error` от attachdetach-controller.
> Суть конфликта одна и та же — см. объяснение ниже.

## Запуск

```bash
kubectl -n lab apply -f pvc.yaml
kubectl -n lab apply -f deploy.yaml
kubectl -n lab get pods -l app=multi-attach-demo -w
```

Ожидаемая картина (~40 секунд после применения):

```
NAME                                 READY   STATUS    RESTARTS   AGE   NODE
multi-attach-demo-7b4f988785-l66pk   1/1     Running   0          41s   k8s-w-1
multi-attach-demo-7b4f988785-ds4x6   0/1     Pending   0          41s   <none>
```

## Задание

1. Выясните по событиям, почему scheduler отбраковал ВСЕ ноды для второго Pod'а.
2. Проверьте режим доступа (AccessMode) у PVC и где физически создался PersistentVolume.
3. Исправьте конфигурацию так, чтобы конфликт был исчерпан.

Начните:

```bash
kubectl -n lab describe pod <имя_зависшего_пода>
kubectl -n lab get pvc shared-data
kubectl get pv -o wide
```

<details>
<summary><strong>Подсказка 1</strong></summary>

В `describe pod` зависшего Pod'а — событие от `default-scheduler`
(снято с этого кластера):

```
0/3 nodes are available:
  1 node(s) didn't match PersistentVolume's node affinity,
  1 node(s) didn't match pod anti-affinity rules,
  1 node(s) had untolerated taint(s).
```

Каждая из трёх нод отвергнута по СВОЕЙ причине. Разберите их по одной:
кто занял «правильную» ноду и почему том нельзя взять с собой на другую?

</details>

<details>
<summary><strong>Подсказка 2</strong></summary>

Посмотрите на манифест `pvc.yaml`: режим доступа — `ReadWriteOnce` (RWO),
«том может быть смонтирован на запись только ОДНОЙ нодой».

Наш кластер использует провижинер `local-path`: PersistentVolume — это каталог
на диске конкретной ноды. Проверьте привязку:

```bash
kubectl get pv -o jsonpath='{.items[0].spec.nodeAffinity}'
```

PV намертво привязан через `nodeAffinity` к ноде, где запустился ПЕРВЫЙ Pod
(`kubernetes.io/hostname In [k8s-w-1]`). А в `deploy.yaml` задан
`podAntiAffinity`, который запрещает двум репликам жить на одной ноде.
Второму Pod'у некуда деваться: на ноде с томом нельзя из-за anti-affinity,
на остальных — нет тома.

</details>

<details>
<summary><strong>Объяснение</strong></summary>

- Первый Pod запускается на ноде А — том создаётся/подключается на ноде А.
- Второй Pod обязан (anti-affinity) уйти на другую ноду, но RWO-том не может
  «переехать» вместе с ним: у local-path PV жёсткая `nodeAffinity`, у облачных
  блочных дисков — запрет на второй attach (та самая `Multi-Attach error`).
- `Deployment` с `replicas > 1` и одним RWO PVC — архитектурная ошибка.

**Ловушка №2 — RollingUpdate.** Даже после уменьшения `replicas` до 1 обычный
`kubectl apply` нового манифеста зависнет: RollingUpdate сначала создаёт НОВЫЙ
Pod, не убив старый. Новый Pod не может встать ни на одну ноду:

```
0/3 nodes are available:
  1 node(s) didn't satisfy existing pods anti-affinity rules,   # нода старого Pod'а
  1 node(s) didn't match PersistentVolume's node affinity,      # чужая нода
  1 node(s) had untolerated taint(s).                           # control-plane
```

Обратите внимание: anti-affinity СУЩЕСТВУЮЩЕГО пода блокирует размещение
нового, даже если у нового пода правило уже убрано — scheduler уважает
правила всех уже работающих подов. Это deadlock: новый ждёт ноду, старый ждёт,
пока новый станет Ready. Поэтому в решении обязательна стратегия `Recreate` —
она сначала удаляет старый Pod (освобождая узел и том) и только потом создаёт
новый.

</details>

<details>
<summary><strong>Решение</strong></summary>

Архитектурные пути:
1. Несколько реплик с общими данными → хранилище с `ReadWriteMany` (NFS/EFS/CephFS).
2. Каждой реплике свой диск → `StatefulSet` с `volumeClaimTemplates`.
3. Данные нужны одному экземпляру → `replicas: 1` + `strategy: Recreate`.

Мы выбираем третий путь:

```bash
kubectl -n lab apply -f ../../solutions/02-multi-attach/deploy.yaml
kubectl -n lab rollout status deploy/multi-attach-demo --timeout=120s
kubectl -n lab get pods -l app=multi-attach-demo
```

Ожидаемый результат: оба старых Pod'а удалены, единственный новый — `1/1 Running`
на ноде, к которой привязан PV.

</details>
