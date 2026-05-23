# 08 · Backup (restic)

> Тема из вакансии: «Поднимать и поддерживать backup-системы (borg / restic / snapshots)»; «Backup-практики (immutable, offsite)».

## Цель и навыки

Понять модель **content-addressed** бэкапов (dedup + шифрование + инкременты) и сделать практический бэкап + restore + retention + offsite + immutable-режим.

После лабы ты:

- объясняешь, почему restic/borg делают **дедуп на уровне chunks** и почему второй бэкап того же дерева почти бесплатен;
- умеешь делать `init / backup / snapshots / restore / forget / prune`;
- настраиваешь **systemd timer** для регулярного снапшота с правильным окном retention;
- знаешь, что такое **append-only repository** и как его сделать на S3/MinIO (rclone serve restic);
- понимаешь правило **3-2-1** (3 копии, 2 разных носителя, 1 offsite) и где в твоей схеме оно соблюдается, а где нет.

## Теоретический минимум

**restic** — open-source бэкап-утилита на Go. Репозиторий — каталог (локальный, sftp, S3, B2, rclone). Файлы режутся на chunks через rolling-hash (CDC), каждый chunk шифруется (AES-256), хеш = адрес. Это даёт:
- **дедупликацию** между бэкапами (один chunk = один блоб);
- **инкременты «бесплатно»** (повторный backup отправит только новые chunks);
- **end-to-end шифрование** — серверу нечего смотреть.

**Immutable backup** = бэкап, который ни клиент, ни злоумышленник с украденным ключом, ни админ репо **не могут удалить** в течение N дней. Реализуется через:
- S3 Object Lock в режиме compliance (даже root-аккаунт не удалит);
- WORM-ленту;
- append-only режим (rclone/rest-server: разрешён `POST`, запрещён `DELETE`).

**3-2-1**: 3 копии (живые данные + 2 бэкапа), 2 разных носителя, 1 offsite. Нет offsite — значит, при пожаре в датацентре ты потерял всё.

**Сценарии восстановления** — это **не** «у меня есть бэкап». Это «я проверял restore последний раз X дней назад, время до восстановления Y минут, потеря данных Z часов (RPO/RTO)».

## Базовая отработка

### Шаг 1. Поставить restic и инициализировать локальный repo

```bash
sudo apt-get install -y restic

mkdir -p /opt/lab/{data,repo}
echo "important data $(date)" > /opt/lab/data/file1.txt
echo "more data" > /opt/lab/data/file2.txt
mkdir /opt/lab/data/subdir && head -c 1M /dev/urandom > /opt/lab/data/subdir/blob.bin

export RESTIC_REPOSITORY=/opt/lab/repo
export RESTIC_PASSWORD='lab-pass-please-change'   # на проде — из Vault!
restic init
```

### Шаг 2. Первый и второй бэкап

```bash
restic backup /opt/lab/data --tag baseline
restic snapshots

echo "fresh data $(date)" > /opt/lab/data/file3.txt
restic backup /opt/lab/data --tag daily

restic snapshots
restic diff $(restic snapshots --json | jq -r '.[-2].short_id') \
            $(restic snapshots --json | jq -r '.[-1].short_id')
```

> Обрати внимание: второй бэкап выполняется за секунды и почти не пишет на диск. Это дедупликация на chunks.

### Шаг 3. Restore

```bash
mkdir -p /tmp/restore-test
restic restore latest --target /tmp/restore-test
diff -r /opt/lab/data /tmp/restore-test/opt/lab/data && echo MATCH
```

Точечный restore одного файла:

```bash
restic restore latest --target /tmp/onefile --include /opt/lab/data/file1.txt
```

Mount как FUSE (читай, как обычную ФС):

```bash
sudo apt-get install -y fuse3
mkdir /tmp/restic-mount
restic mount /tmp/restic-mount &
ls /tmp/restic-mount/snapshots/
fusermount -u /tmp/restic-mount
```

### Шаг 4. Retention и prune

```bash
restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
restic snapshots
```

Это политика: «храним 7 ежедневных, 4 еженедельных, 6 ежемесячных, всё остальное удаляем и физически освобождаем место». **Обязательно прогнать на проде хотя бы раз в неделю**, иначе репо растёт.

### Шаг 5. Автоматизация — systemd timer

```bash
sudo tee /etc/restic.env <<'EOF'
RESTIC_REPOSITORY=/opt/lab/repo
RESTIC_PASSWORD=lab-pass-please-change
EOF
sudo chmod 0600 /etc/restic.env

sudo tee /usr/local/bin/lab-backup.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source /etc/restic.env; export RESTIC_REPOSITORY RESTIC_PASSWORD
restic backup /opt/lab/data --tag scheduled
restic forget --keep-daily 7 --keep-weekly 4 --prune
EOF
sudo chmod +x /usr/local/bin/lab-backup.sh

sudo tee /etc/systemd/system/lab-backup.service <<'EOF'
[Unit]
Description=Lab restic backup
[Service]
Type=oneshot
ExecStart=/usr/local/bin/lab-backup.sh
EOF

sudo tee /etc/systemd/system/lab-backup.timer <<'EOF'
[Unit]
Description=Hourly lab backup (lab-only; on prod — раз в сутки в окно)
[Timer]
OnCalendar=hourly
Persistent=true
[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now lab-backup.timer
systemctl list-timers lab-backup.timer
```

## Расширенная отработка

### Задача 1. Offsite на MinIO (S3-совместимый)

```bash
docker run -d --name minio \
  -p 9000:9000 -p 9001:9001 \
  -e MINIO_ROOT_USER=lab \
  -e MINIO_ROOT_PASSWORD=lab-very-strong-pass \
  -v ~/lab08/minio:/data \
  minio/minio:latest server /data --console-address ':9001'

docker exec minio mc alias set local http://127.0.0.1:9000 lab lab-very-strong-pass
docker exec minio mc mb local/restic
```

Перенастрой restic:

```bash
export RESTIC_REPOSITORY=s3:http://127.0.0.1:9000/restic
export AWS_ACCESS_KEY_ID=lab
export AWS_SECRET_ACCESS_KEY=lab-very-strong-pass
export RESTIC_PASSWORD=lab-pass-please-change
restic init
restic backup /opt/lab/data --tag s3-offsite
```

> На проде это не localhost, а другой регион/провайдер. Без offsite — нет 3-2-1.

### Задача 2. Immutable / append-only

На MinIO включи **Object Lock** при создании bucket (`mc retention set --default compliance 30d local/restic`). Попробуй `restic forget --prune` — restic пожалуется, что не может удалить старые pack-files. Это и есть compliance-режим: даже компрометация ключа не даст удалить данные раньше срока.

Альтернатива без S3: `rest-server --append-only --private-repos --path /srv/restic` на отдельной VM. restic к нему подключается через `RESTIC_REPOSITORY=rest:http://...`.

### Задача 3. Тест восстановления (DR drill)

Самое важное. Раз в N времени делаешь:

```bash
restic restore latest --target /tmp/dr-$(date +%Y%m%d)
# запускаешь приложение/БД из восстановленного каталога
# проверяешь — стартует ли, целы ли данные
```

Запиши: **сколько времени ушло** от «решили восстановить» до «сервис принимает запросы». Это твой реальный RTO. Без drill — RTO у тебя «неизвестно», и это самый плохой ответ на собесе.

## Acceptance criteria

- [ ] `restic snapshots` показывает ≥2 снапшота с разными tag.
- [ ] `restic restore latest` восстанавливает дерево, `diff -r` чистый.
- [ ] `lab-backup.timer` стоит `active (waiting)`, после хода времени появляется новый snapshot.
- [ ] `restic forget --keep-daily 7 …` удаляет лишние снапшоты, `restic stats raw-data` уменьшается.
- [ ] (Расширенная) бэкап ушёл в MinIO и виден в его консоли (`:9001`).

## Что обсудить на ревью

1. Чем restic отличается от borg? (Подсказка: storage backends, ключ-шифрование, prune-производительность.)
2. Что произойдёт, если ты потеряешь `RESTIC_PASSWORD`? — данные **навсегда** недоступны. Где хранишь? → [Vault](../07-secrets-vault/).
3. Почему `forget` без `--prune` ничего не освобождает на диске?
4. Что такое RPO и RTO? Назови свои числа.
5. Можно ли сделать «бэкап БД» через restic поверх `/var/lib/postgresql`? — **нет**, без `pg_basebackup`/`pg_dump` — это снимок несогласованного состояния.

## Грабли

| Симптом | Причина | Лечение |
|---------|---------|---------|
| `wrong password or no key found` | потерян `RESTIC_PASSWORD` | спасения нет; хранить в Vault и/или KMS |
| Репо растёт несмотря на `forget` | без `--prune` блоки не удаляются | `forget … --prune` или периодический `prune` |
| Бэкап медленный на сети | один большой файл = один chunk-stream | разбей дерево, многопоток `--read-concurrency` |
| `repository is already locked` | прошлый бэкап упал, оставил lock | `restic unlock` (после проверки, что никто не работает) |
| Нет offsite | бэкап на тот же диск, что и данные | minimum — другой volume; лучше — другой провайдер |
