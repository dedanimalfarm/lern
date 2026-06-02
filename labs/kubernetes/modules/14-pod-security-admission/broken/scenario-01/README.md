# Сценарий 01: под отклонён Pod Security Admission (restricted)

## Симптом

`kubectl apply` пода падает с ошибкой ещё ДО создания — API-сервер отклоняет
объект с сообщением про `violates PodSecurity "restricted"`.

## Запуск

```bash
kubectl apply -f bad-pod.yaml
# Error from server (Forbidden): ... violates PodSecurity "restricted:latest":
#   allowPrivilegeEscalation != false, unrestricted capabilities, runAsNonRoot != true,
#   seccompProfile ...
```

## Задание

1. Прочитайте, какие именно требования restricted нарушены.
2. Приведите под в соответствие профилю.
3. Убедитесь, что он создаётся.

<details>
<summary><strong>Подсказка</strong></summary>

PSA проверяет на admission (до записи в etcd). Профиль `restricted` требует:
`runAsNonRoot: true`, `allowPrivilegeEscalation: false`,
`capabilities.drop: [ALL]`, `seccompProfile.type: RuntimeDefault` — и на уровне
пода, и на уровне контейнера.

</details>

<details>
<summary><strong>Объяснение</strong></summary>

- Namespace `lab-restricted` имеет `pod-security.kubernetes.io/enforce: restricted`.
- `bad-pod` использует root-образ без securityContext → нарушает сразу несколько
  требований restricted.
- API-сервер (PSA admission) отклоняет под — он даже не создаётся.

</details>

<details>
<summary><strong>Решение</strong></summary>

Добавить полный `securityContext` (см. `../../manifests/good-pod.yaml`):

```bash
kubectl apply -f ../../manifests/good-pod.yaml   # этот проходит restricted
kubectl -n lab-restricted get pod good-pod
```

</details>
