# Сценарий 02: Пропущенный Toleration

## Симптом

Deployment применён, вы настроили `nodeSelector`, чтобы запустить Pod строго на Control Plane ноде (мастер-ноде). Но Pod остается в состоянии `Pending`.

## Запуск

```bash
kubectl -n lab apply -f deploy.yaml
kubectl -n lab get pods -l app=cp-only-app -w
```

## Задание

1. Выясните, почему Scheduler не может разместить Pod на мастер-ноде.
2. Проверьте свойства мастер-ноды.
3. Добавьте необходимое разрешение (toleration) в манифест, чтобы Pod успешно запустился.

Начните:

```bash
kubectl -n lab describe pod -l app=cp-only-app
kubectl get nodes -l node-role.kubernetes.io/control-plane
```

<details>
<summary><strong>Подсказка 1</strong></summary>

В логах событий (`kubectl describe pod ...`) вы увидите сообщение от `default-scheduler` (снято с этого кластера):

```
0/3 nodes are available: 1 node(s) had untolerated taint(s),
2 node(s) didn't match Pod's node affinity/selector.
```

Это значит, что 2 воркер-ноды отброшены из-за `nodeSelector`, а 1 мастер-нода отброшена из-за `taint`. Заметьте: scheduler НЕ называет сам taint — какой именно taint мешает, придётся выяснить, изучив ноду (подсказка 2).

</details>

<details>
<summary><strong>Подсказка 2</strong></summary>

По умолчанию Kubernetes защищает Control Plane ноды от пользовательской нагрузки с помощью "пятен" (taints).
Посмотрите taints на мастер-ноде:

```bash
kubectl describe node -l node-role.kubernetes.io/control-plane | grep Taints
```
Вы увидите: `Taints: node-role.kubernetes.io/control-plane:NoSchedule`

</details>

<details>
<summary><strong>Объяснение</strong></summary>

- `nodeSelector` говорит планировщику: "Выбери ноду с таким лейблом" (мастер-ноду).
- Но на мастер-ноде висит `Taint` с эффектом `NoSchedule`.
- `Taint` запрещает планировать на эту ноду любые Pod'ы, если у них нет соответствующего "иммунитета" (`Toleration`).
- Поскольку `Toleration` не прописан, Pod застревает в `Pending`.

</details>

<details>
<summary><strong>Решение</strong></summary>

Добавьте секцию `tolerations` в `spec.template.spec` вашего `deploy.yaml`:

```yaml
      tolerations:
      - key: "node-role.kubernetes.io/control-plane"
        operator: "Exists"
        effect: "NoSchedule"
```

Примените исправленный манифест:
```bash
kubectl -n lab apply -f ../../solutions/02-missing-toleration/deploy.yaml
kubectl -n lab get pods -l app=cp-only-app -w
```

</details>
