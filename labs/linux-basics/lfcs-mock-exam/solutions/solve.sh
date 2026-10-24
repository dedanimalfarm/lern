#!/usr/bin/env bash
# Эталонные решения пробного экзамена. Подсматривайте только после попытки!
#
# Скрипт можно и прочитать как разбор, и запустить: sudo ./solutions/solve.sh
# (на CI он доказывает, что verify.sh засчитывает правильные решения).
# Многие задачи решаются несколькими способами — в комментариях указаны
# альтернативы и типичные ошибки, на которые рассчитаны ловушки стенда.
set -euo pipefail

E=/opt/exam
A=$E/answers
[ "$(id -u)" -eq 0 ] || { echo "Запустите от root"; exit 2; }

# 1. man -k "password expiry" или apropos expiry → chage(1)
echo chage > "$A/01.txt"

# 2. Уровень в скобках: экранируем [ ], иначе это класс символов grep.
grep -c '\[ERROR\]' "$E/logs/app.log" > "$A/02.txt"
grep '\[ERROR\]' "$E/logs/app.log" | grep -i disk > "$A/02-disk.txt"

# 3. stdout и stderr в разные файлы.
"$E/bin/report.sh" > "$A/03.out" 2> "$A/03.err"

# 4. -size +1M: «больше 1 МиБ» после округления вверх; ровно 1 МиБ не подходит.
#    Ловушки стенда: one.bin (ровно 1 МиБ), big2.bin (владелец root).
find "$E/data" -type f -user webuser -size +1M > "$A/04.txt"

# 5. cp --parents повторяет путь, который ему передали, поэтому заходим в /opt/exam
#    и даём относительные пути etc/... (с абсолютными получится backup/etc/opt/exam/etc/...).
mkdir -p "$E/backup"
( cd "$E" && find etc -type f -name '*.conf' -exec cp --parents {} backup/ \; )

# 6. -mtime +7 — больше 7 полных суток; mv сохраняет время изменения.
mkdir -p "$E/archive/old"
find "$E/tmp" -maxdepth 1 -type f -mtime +7 -exec mv -t "$E/archive/old/" {} +

# 7. Якоря ^ и $: глобальная замена «debug = true» задела бы комментарий в последней строке.
sed -i -e 's/^#max_connections = .*/max_connections = 200/' \
       -e 's/^debug = true$/debug = false/' "$E/config/app.conf"

# 8. Точное сравнение поля: grep IT зацепил бы и отдел ITOps.
awk -F, '$2 == "IT" {print $1, $3}' "$E/data/employees.csv" | sort -k2,2nr | head -3 > "$A/08.txt"

# 9. Классика: поле → sort → uniq -c → sort -rn → head.
awk '{print $1}' "$E/logs/access.log" | sort | uniq -c | sort -rn | head -5 > "$A/09.txt"

# 10. -C меняет каталог, чтобы пути в архиве начинались с project/.
tar -czf "$E/backup/project.tar.gz" -C "$E" --exclude=project/logs --exclude='*.tmp' project

# 11. После имени архива — имя нужного файла ровно как в tar -tf; -C — куда распаковать.
#     Копировать из /opt/exam/www нельзя: там уже изменённая версия.
mkdir -p "$E/restore"
tar -xJf "$E/archive/site.tar.xz" -C "$E/restore" site/conf/nginx.conf

# 12. -e — дата, после которой вход запрещён; проверка: chage -l deploy.
groupadd -g 2050 devops
useradd -m -d /home/deploy -s /bin/bash -G devops -e 2030-12-31 deploy

# 13. Отдельный файл в sudoers.d с правами 0440 и проверка синтаксиса до использования.
echo 'deploy ALL=(root) NOPASSWD: /usr/bin/journalctl' > /etc/sudoers.d/deploy
chmod 0440 /etc/sudoers.d/deploy
visudo -cq

# 14. 2 — SGID: новые файлы наследуют группу каталога.
mkdir -p /srv/devops
chown root:devops /srv/devops
chmod 2770 /srv/devops

# 15. ACL: x на каталоге (пройти внутрь) и r на файле. chmod o+r нарушил бы условие
#     (и открыл бы файл для guest).
setfacl -m u:auditor:x "$E/secure"
setfacl -m u:auditor:r "$E/secure/report.txt"

# 16. -n обязателен: current указывает на каталог, и без -n ln -sf создал бы ссылку
#     ВНУТРИ releases/v1, а current остался бы прежним.
ln -sfn "$E/releases/v2" "$E/current"
ln "$E/data/docs/master.txt" "$E/data/docs/hard.txt"

# 17. /etc/profile.d читается при входе всеми; ~/.profile — только этим пользователем.
#     (В конец ~/.bashrc писать нельзя: в Ubuntu он выходит для неинтерактивной оболочки.)
echo 'export EXAM_ENV=lfcs' > /etc/profile.d/exam.sh
echo 'export APP_HOME=/opt/app' >> /home/deploy/.profile

# 18. umask для одного пользователя — в его ~/.profile.
echo 'umask 027' >> /home/deploy/.profile

echo "Решения применены. Проверка: sudo ./verify.sh"
