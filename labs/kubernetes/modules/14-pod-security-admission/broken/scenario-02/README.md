# Сценарий 02: `kubectl apply` прошёл, а подов нет

## Симптом

В отличие от сценария 01, ошибки при apply **нет** — но приложение не поднимается:

```bash
kubectl -n lab get deploy latest-app
# NAME         READY   UP-TO-DATE   AVAILABLE   AGE
# latest-app   0/1     0            0           1m      <- UP-TO-DATE 0
kubectl -n lab get pods -l app=latest-app
# No resources found in lab namespace.
```

## Запуск

```bash
kubectl apply -f manifests/vap-no-latest.yaml
kubectl -n lab apply -f broken/scenario-02/deploy.yaml
sleep 5; kubectl -n lab get deploy,rs,pods -l app=latest-app
```

## Задание

1. Найдите, на каком уровне (Deployment → ReplicaSet → Pod) всё останавливается.
2. Прочитайте причину отказа и назовите политику, которая его выдала.
3. Исправьте манифест так, чтобы политика пропустила под.

Начните:

```bash
kubectl -n lab describe rs -l app=latest-app | grep -A4 '^Events'
kubectl -n lab get deploy latest-app -o jsonpath='{.status.conditions[?(@.type=="ReplicaFailure")]}{"\n"}'
```

<details>
<summary><strong>Подсказка 1</strong></summary>

Deployment и ReplicaSet — не поды: admission проверяет `pods`, поэтому создание Deployment проходит, а отказ приходит ReplicaSet-контроллеру при попытке создать под.

</details>

<details>
<summary><strong>Подсказка 2</strong></summary>

В Events ReplicaSet: `Error creating: ... ValidatingAdmissionPolicy 'no-latest-tag' with binding 'no-latest-tag-binding' denied request: образы с тегом ':latest' или без тега запрещены`.

</details>

<details>
<summary><strong>Объяснение</strong></summary>

- `ValidatingAdmissionPolicy no-latest-tag` привязана к namespace `lab` и проверяет
  **поды**. Deployment с `nginx:latest` создаётся без ошибок, а его ReplicaSet при создании
  пода получает `Deny` — это видно только в событиях RS и в условии `ReplicaFailure`.
- Это самый коварный вид отказа admission: CI видит успешный `apply`, а сервис не запускается.
- Отсюда правило: гонять политики и на шаблонах workload'ов (`kubectl apply --dry-run=server`
  не поможет — проверяйте `matchConstraints` с `apps/v1 deployments` или тестируйте под).

</details>

<details>
<summary><strong>Решение</strong></summary>

Запинить образ — `solutions/scenario-02/deploy.yaml` (`nginx:1.27-alpine`):

```bash
kubectl -n lab apply -f solutions/scenario-02/deploy.yaml
kubectl -n lab rollout status deploy/latest-app --timeout=60s
```

</details>
