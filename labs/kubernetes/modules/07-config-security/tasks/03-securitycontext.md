# 03-securitycontext

## Задача
Запустить workload с ограничениями безопасности.

## Минимум
- `runAsNonRoot: true`
- `allowPrivilegeEscalation: false`
- `readOnlyRootFilesystem: true` (если приложение позволяет)
## Проверка
```bash
kubectl -n lab get pod <pod> -o jsonpath='{.spec.securityContext}{"\n"}{.spec.containers[0].securityContext}{"\n"}'
kubectl -n lab exec <pod> -- id
kubectl -n lab exec <pod> -- sh -c 'touch /probe && echo writable || echo read-only'
```

## Ожидаемый результат
- `id` показывает не-root UID; попытка записи в корень ФС отвечает `Read-only file system`.
- Под с образом, который стартует от root (например, `nginx` без rootless-варианта),
  при `runAsNonRoot: true` падает с `CreateContainerConfigError: container has runAsNonRoot
  and image will run as root` — вы знаете, как это чинится (`runAsUser` или образ
  `-unprivileged`).
