#!/usr/bin/env bash
# Типичные НЕВЕРНЫЕ решения — проверка, что ловушки стенда работают.
# Запускается из ci-selftest.sh mistakes на свежем стенде; verify.sh обязан
# поставить FAIL каждой задаче из списка MISTAKE_TASKS.
# Задача 12 решается верно, чтобы зависимые от неё задачи падали по своей причине.
set -euo pipefail

E=/opt/exam
A=$E/answers

# 02: забыли -i — пропущены строки "Disk" и "DISK"
grep -c '\[ERROR\]' "$E/logs/app.log" > "$A/02.txt"
grep '\[ERROR\]' "$E/logs/app.log" | grep disk > "$A/02-disk.txt"

# 03: оба потока свалены в 03.out (2>&1), в 03.err — только повторный запуск
"$E/bin/report.sh" > "$A/03.out" 2>&1
"$E/bin/report.sh" 2> "$A/03.err" > /dev/null

# 04: забыли -user — попал big2.bin, владелец которого root
find "$E/data" -type f -size +1M > "$A/04.txt"

# 05: абсолютные пути в cp --parents — получилось backup/etc/opt/exam/etc/...
mkdir -p "$E/backup/etc"
find "$E/etc" -name '*.conf' -exec cp --parents {} "$E/backup/etc/" \;

# 06: скопировали вместо переноса
mkdir -p "$E/archive/old"
find "$E/tmp" -type f -mtime +7 -exec cp {} "$E/archive/old/" \;

# 07: замена без якорей задела и комментарий в последней строке
sed -i -e 's/^#max_connections = .*/max_connections = 200/' -e 's/debug = true/debug = false/' "$E/config/app.conf"

# 08: grep IT зацепил отдел ITOps
grep ',IT' "$E/data/employees.csv" | awk -F, '{print $1, $3}' | sort -k2,2nr | head -3 > "$A/08.txt"

# 09: uniq -c без предварительного sort — считает только подряд идущие повторы
awk '{print $1}' "$E/logs/access.log" | uniq -c | sort -rn | head -5 > "$A/09.txt"

# 10: без -C — пути в архиве начинаются с opt/exam/project
tar -czf "$E/backup/project.tar.gz" --exclude="$E/project/logs" --exclude='*.tmp' "$E/project" 2>/dev/null

# 11: скопировали «живую» версию вместо распаковки из архива
mkdir -p "$E/restore/site/conf"
cp "$E/www/site/conf/nginx.conf" "$E/restore/site/conf/"

# 12: верно — от неё зависят 13, 14, 17, 18
groupadd -g 2050 devops
useradd -m -d /home/deploy -s /bin/bash -G devops -e 2030-12-31 deploy

# 13: разрешили всё
echo 'deploy ALL=(root) NOPASSWD: ALL' > /etc/sudoers.d/deploy
chmod 0440 /etc/sudoers.d/deploy

# 14: забыли SGID
mkdir -p /srv/devops; chown root:devops /srv/devops; chmod 0770 /srv/devops

# 15: открыли всем через chmod вместо ACL
chmod o+x "$E/secure"; chmod o+r "$E/secure/report.txt"

# 16: ln -sf без -n — ссылка создана внутри releases/v1
ln -sf "$E/releases/v2" "$E/current"
ln -s "$E/data/docs/master.txt" "$E/data/docs/hard.txt"

# 17: export в конце ~/.bashrc — неинтерактивный вход его не видит
echo 'export EXAM_ENV=lfcs' >> /home/auditor/.bashrc
echo 'export APP_HOME=/opt/app' >> /home/deploy/.bashrc

# 18: umask для всех вместо одного пользователя
echo 'umask 027' > /etc/profile.d/umask.sh

echo "Типичные ошибки применены."
