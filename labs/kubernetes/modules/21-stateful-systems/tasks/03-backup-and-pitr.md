# 03 — Бэкап по расписанию, ручной Backup и PITR

## Задача
Создать `ScheduledBackup`, запустить ручной `Backup`, увидеть, почему на стенде без
объектного хранилища он не завершается, и описать конфигурацию, при которой заработают
бэкапы и PITR.

## Проверка
```bash
kubectl apply -f manifests/backup.yaml
kubectl -n lab get scheduledbackup
cat <<EOF | kubectl apply -f -
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata: { name: manual-backup, namespace: lab }
spec:
  cluster: { name: my-db }
EOF
sleep 20
kubectl -n lab get backup manual-backup
kubectl -n lab describe backup manual-backup | tail -8
kubectl -n lab get cluster my-db -o jsonpath='{.spec.backup}'; echo
```

## Ожидаемый результат
- `ScheduledBackup/my-db-backup` создан, `SUSPENDED false`.
- Ручной `Backup` **не** переходит в `completed`: `.spec.backup` у кластера пустой,
  в `describe` — ошибка об отсутствии `barmanObjectStore` (S3-совместимого хранилища на
  стенде нет).
- Вы написали (не применяя) секцию `spec.backup.barmanObjectStore` с `destinationPath:
  s3://…`, `endpointURL` (например, MinIO в кластере) и `s3Credentials`, и объяснили, зачем
  для PITR нужен непрерывный архив WAL и как `retentionPolicy` связан с глубиной
  `recoveryTarget.targetTime`.
