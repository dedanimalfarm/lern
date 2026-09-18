# 01-deployment-rollout

## Шаги
1. Применить `deployment/v1`.
2. Обновить до `deployment/v2`.
3. Проверить историю rollout.
4. Выполнить rollback.

## Команды
```bash
kubectl -n lab apply -f manifests/deployment/v1
kubectl -n lab apply -f manifests/deployment/v2
kubectl -n lab rollout history deploy/workload-demo
kubectl -n lab rollout undo deploy/workload-demo
```
## Ожидаемый результат
- После apply v2 `rollout history` показывает две ревизии; `kubectl -n lab get rs` — два
  ReplicaSet, у старого `DESIRED 0`.
- После `rollout undo` Deployment снова на образе v1, а в истории появилась **третья**
  ревизия (откат — это новый rollout, а не удаление).
- Вы можете объяснить, почему без `--record`/аннотации `kubernetes.io/change-cause`
  колонка `CHANGE-CAUSE` пуста и как её заполнять.
