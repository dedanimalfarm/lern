#!/usr/bin/env bash
# Подготовка стенда пробного экзамена (labs/linux-basics/lfcs-mock-exam).
#
# Запускать от root на ОДНОРАЗОВОЙ машине: учебной VM или docker-контейнере.
# Скрипт создаёт пользователей (auditor, guest, webuser) и данные в /opt/exam,
# поэтому на рабочей машине его запускать не нужно.
#
# Скрипт ничего не удаляет и не сбрасывает: если /opt/exam уже есть, он
# откажется работать. Для нового прогона создайте новый контейнер или VM.
#
# Данные детерминированы (без случайных чисел), поэтому verify.sh может
# сравнивать ответы с заранее известными значениями.
set -euo pipefail

EXAM=/opt/exam

die() { echo "setup.sh: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "запустите от root: sudo $0"
[ ! -e "$EXAM" ] || die "$EXAM уже существует — стенд уже подготовлен. Для нового прогона нужна новая VM или контейнер."

# Всё, на что опираются задачи и проверка. Пакеты в Ubuntu/Debian: sudo acl xz-utils.
missing=""
for cmd in sudo visudo runuser su useradd groupadd chage setfacl getfacl tar gzip xz awk sed find stat; do
  command -v "$cmd" >/dev/null 2>&1 || missing="$missing $cmd"
done
[ -z "$missing" ] || die "не найдены команды:$missing (Ubuntu/Debian: apt install -y sudo acl xz-utils)"

echo "== пользователи"
for u in auditor guest webuser; do
  id "$u" >/dev/null 2>&1 || useradd -m -s /bin/bash "$u"
done

echo "== /opt/exam"
mkdir -p "$EXAM"/{answers,bin,config,logs,data,etc,tmp,project,archive,www,releases,secure}
chmod 755 "$EXAM" "$EXAM/answers"

# --- задача 2: журнал приложения (300 строк, уровень в квадратных скобках)
awk 'BEGIN {
  split("INFO WARNING ERROR INFO INFO ERROR WARNING INFO ERROR INFO", lv, " ")
  split("disk latency high|Disk write failed on /dev/sdb|DISK quota exceeded for /home|connection reset by peer|memory usage above 90%|service restarted|backup completed|user login failed|config reloaded|timeout talking to db", msg, "|")
  # Уровень меняется каждую строку, сообщение — блоками по 10 строк: так каждое
  # сообщение встречается с каждым уровнем (есть и ERROR, и WARNING со словом disk).
  for (i = 1; i <= 300; i++)
    printf "2026-10-%02d %02d:%02d:%02d [%s] %s\n", (i % 28) + 1, i % 24, i % 60, (i * 13) % 60, lv[(i % 10) + 1], msg[(int(i / 10) % 10) + 1]
}' > "$EXAM/logs/app.log"

# --- задача 9: журнал веб-сервера; у IP разное число запросов, ничьих в топ-5 нет
awk 'BEGIN {
  n = split("10.0.0.5 192.168.1.20 10.0.0.7 172.16.0.3 192.168.1.33 10.0.0.9 172.16.0.8 192.168.1.40 10.0.0.12 172.16.0.11", ip, " ")
  split("23 19 17 13 11 7 5 3 2 1", cnt, " ")
  k = 0
  for (j = 1; j <= n; j++) for (c = 1; c <= cnt[j]; c++) { k++; line[k] = ip[j] }
  # детерминированное перемешивание: позиция (i * 37) mod k (37 и 101 взаимно просты)
  for (i = 0; i < k; i++) {
    p = (i * 37) % k + 1
    printf "%s - - [24/Oct/2026:10:%02d:%02d +0000] \"GET /page/%d HTTP/1.1\" 200 %d\n", line[p], i % 60, (i * 7) % 60, i % 9, 200 + i
  }
}' > "$EXAM/logs/access.log"

# --- задача 3: скрипт, который пишет и в stdout, и в stderr
cat > "$EXAM/bin/report.sh" <<'EOF'
#!/bin/sh
echo "report: start"
echo "warning: cache is stale" >&2
echo "report: 42 records"
echo "error: 1 record skipped" >&2
echo "report: done"
EOF
chmod 755 "$EXAM/bin/report.sh"

# --- задача 7: конфиг для правки через sed
cat > "$EXAM/config/app.conf" <<'EOF'
# Application settings
listen = 0.0.0.0:8080
#max_connections = 100
debug = true
log_level = info
# debug = true is not allowed in production
EOF

# --- задача 4: файлы разного размера и владельца (-size +1M и округление)
mkdir -p "$EXAM/data"/{media,backups,cache/sub,docs}
head -c 2097152 /dev/zero > "$EXAM/data/media/big1.bin"       # 2 МиБ, webuser — подходит
head -c 1048576 /dev/zero > "$EXAM/data/media/one.bin"        # ровно 1 МиБ — НЕ больше 1 МиБ
head -c 1048000 /dev/zero > "$EXAM/data/media/almost.bin"     # чуть меньше 1 МиБ
head -c 1572864 /dev/zero > "$EXAM/data/cache/sub/big3.bin"   # 1,5 МиБ, webuser — подходит
head -c 102400  /dev/zero > "$EXAM/data/cache/small.bin"      # 100 КиБ
head -c 3145728 /dev/zero > "$EXAM/data/backups/big2.bin"     # 3 МиБ, но владелец root
chown -R webuser:webuser "$EXAM/data/media" "$EXAM/data/cache"
# --- задача 16: файл для жёсткой ссылки
echo "master data v1" > "$EXAM/data/docs/master.txt"

# --- задача 8: сотрудники; отдел ITOps — ловушка для grep IT
cat > "$EXAM/data/employees.csv" <<'EOF'
name,dept,salary
anna,IT,5200
boris,HR,4100
clara,ITOps,9900
denis,IT,6100
elena,Sales,7300
fedor,IT,4800
galina,IT,7000
igor,ITOps,8800
kira,HR,3900
lev,IT,5600
maria,Sales,6900
nikita,IT,6500
EOF

# --- задача 5: дерево конфигов (не только .conf)
mkdir -p "$EXAM/etc"/{app,db,web/nginx}
echo "top=1"            > "$EXAM/etc/top.conf"
echo "name=app"         > "$EXAM/etc/app/app.conf"
echo "example only"     > "$EXAM/etc/app/app.conf.example"
echo "host=localhost"   > "$EXAM/etc/db/db.conf"
echo "remember backups" > "$EXAM/etc/db/notes.txt"
echo "server_name lab;" > "$EXAM/etc/web/nginx/site.conf"
echo "text/html html;"  > "$EXAM/etc/web/nginx/mime.types"

# --- задача 6: временные файлы разного возраста
for f in old1.tmp:10 old2.log:30 edge.tmp:6 new1.tmp:1 new2.log:0; do
  name=${f%%:*}; days=${f##*:}
  echo "$name" > "$EXAM/tmp/$name"
  touch -d "$days days ago" "$EXAM/tmp/$name"
done

# --- задача 10: проект с логами и временными файлами
mkdir -p "$EXAM/project"/{src,logs/old}
echo "# Project"         > "$EXAM/project/README.md"
echo "env: prod"         > "$EXAM/project/config.yml"
echo "int main(){}"      > "$EXAM/project/src/main.c"
echo "int util(){}"      > "$EXAM/project/src/util.c"
echo "cache"             > "$EXAM/project/src/cache.tmp"
echo "build"             > "$EXAM/project/build.tmp"
echo "log"               > "$EXAM/project/logs/app.log"
echo "old log"           > "$EXAM/project/logs/old/2025.log"

# --- задача 11: архив сайта; живая копия потом меняется, чтобы её нельзя было
# просто скопировать вместо распаковки
mkdir -p "$EXAM/www/site"/{conf,html}
printf 'worker_processes 2;\nevents { worker_connections 512; }\n' > "$EXAM/www/site/conf/nginx.conf"
echo "<h1>lab</h1>" > "$EXAM/www/site/html/index.html"
echo "ok"           > "$EXAM/www/site/html/health.txt"
tar -cJf "$EXAM/archive/site.tar.xz" -C "$EXAM/www" site
sed -i 's/worker_processes 2;/worker_processes 4;/' "$EXAM/www/site/conf/nginx.conf"

# --- задача 16: релизы и ссылка current -> v1 (на каталог: ловушка ln -sf без -n)
mkdir -p "$EXAM/releases"/{v1,v2}
echo "v1" > "$EXAM/releases/v1/VERSION"
echo "v2" > "$EXAM/releases/v2/VERSION"
ln -s "$EXAM/releases/v1" "$EXAM/current"

# --- задача 15: закрытый каталог с отчётом
echo "quarterly report" > "$EXAM/secure/report.txt"
chown -R root:root "$EXAM/secure"
chmod 750 "$EXAM/secure"
chmod 640 "$EXAM/secure/report.txt"

date +%s > "$EXAM/.started"
echo
echo "Стенд готов. Задачи — в TASKS.md, проверка — sudo ./verify.sh"
echo "Время пошло: $(date '+%F %T'). На экзамен — 2 часа."
