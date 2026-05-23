# 01 · Linux baseline (systemd, users, ssh, sudo)

> Тема из вакансии: «Уверенный Linux (Ubuntu): systemd, users, ssh, networking».

## Цель и навыки

После этой лабы ты умеешь **руками** (без Ansible) привести свежую Ubuntu-VM в безопасное минимально-боевое состояние и объясняешь, что именно делаешь и зачем. Дальше эти же шаги будут автоматизированы в [`03-ansible-baseline`](../03-ansible-baseline/).

Что ты должен уметь после:

- читать состояние сервиса через `systemctl status`/`journalctl -u`;
- создавать пользователя, давать ему sudo-права через drop-in в `/etc/sudoers.d/`;
- настраивать вход по ssh-ключу и **запрещать** вход по паролю;
- понимать разницу между `/etc/sshd_config` и каталогом `sshd_config.d/`;
- писать unit-файл для собственного сервиса и включать его в автозагрузку.

## Теоретический минимум

**systemd** — система инициализации Ubuntu (PID 1). Управляет сервисами (`*.service`), таймерами (`*.timer`), точками монтирования (`*.mount`), целями (`*.target`). Логи — в journald, читаются через `journalctl`.

**Юниты** живут в двух местах:
- `/lib/systemd/system/` — то, что положили пакеты (не трогаем);
- `/etc/systemd/system/` — наши переопределения и собственные юниты.

**Пользователи и группы** — `/etc/passwd`, `/etc/group`, `/etc/shadow`. Команды: `useradd`, `usermod`, `groupadd`, `passwd`. Sudo даёт `sudo` (через членство в группе `sudo`) либо файл в `/etc/sudoers.d/`.

**SSH** — пакет `openssh-server`, демон `ssh.service` (имя именно `ssh`, не `sshd`, в Ubuntu). Конфиг `/etc/ssh/sshd_config` плюс drop-in `/etc/ssh/sshd_config.d/*.conf` (включаются `Include`). Ключи — в `~/.ssh/authorized_keys` пользователя, права строго `0600`, владелец = сам пользователь.

**Правило least privilege** (тема Части C): сервис должен работать от своего пользователя, sudo выдаётся точечно (`Cmnd_Alias`), root-логин по ssh запрещён. Если ты выдал NOPASSWD на ALL — это **только** для cloud-образа в лабе, на проде так нельзя.

Минимум документации: `man systemd.unit`, `man sshd_config`, `man sudoers`.

## Базовая отработка

Выполняй на VM из [`00-setup`](../00-setup/). Подключаешься как `ubuntu` (или эквивалент).

### Шаг 1. Карта системы

```bash
hostnamectl                       # ОС, kernel, hostname
systemctl list-units --type=service --state=running | head
systemctl --failed                # упавшие сервисы (на свежей VM пусто)
journalctl -p err -b              # ошибки с момента последней загрузки
```

Запиши в блокнот: какой `Static hostname`, какое ядро, какие сервисы упали (если есть — почему?).

### Шаг 2. Свой пользователь и sudo

```bash
sudo adduser --disabled-password --gecos "" deploy
sudo usermod -aG sudo deploy
echo 'deploy ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/90-deploy
sudo chmod 0440 /etc/sudoers.d/90-deploy
sudo visudo -cf /etc/sudoers.d/90-deploy     # проверка синтаксиса
```

> **Почему drop-in, а не правка `/etc/sudoers`?** Если ты сломаешь синтаксис `sudoers`, ты теряешь sudo. `visudo` спасает интерактивно, но в скрипте — нет. drop-in-файлы атомарны и удаляются одной командой при откате.

### Шаг 3. Ключи и жёсткая ssh-конфигурация

С контрольной машины:

```bash
ssh-copy-id -i ~/.ssh/vast.pub deploy@<VM-IP>
```

На VM:

```bash
sudo tee /etc/ssh/sshd_config.d/99-hardening.conf >/dev/null <<'EOF'
PasswordAuthentication no
PermitRootLogin no
KbdInteractiveAuthentication no
EOF

sudo sshd -t                      # проверка конфига — обязательно ДО reload
sudo systemctl reload ssh
```

> **Никогда не делай `restart ssh` без проверки `sshd -t`.** Сломанный конфиг = упавший демон = ты в чёрной дыре. `reload` мягче `restart`, а `sshd -t` ловит синтаксис.

Проверь из новой сессии (старую не закрывай!):

```bash
ssh -o PreferredAuthentications=password deploy@<VM-IP>   # должен отказать
ssh deploy@<VM-IP> 'whoami; sudo -n true && echo SUDO_OK' # должен работать
```

### Шаг 4. Свой systemd-сервис

Сделай минимальный сервис, который раз в минуту пишет в журнал «I'm alive».

```bash
sudo tee /usr/local/bin/heartbeat.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
logger -t heartbeat "I'm alive at $(date -Iseconds)"
EOF
sudo chmod +x /usr/local/bin/heartbeat.sh

sudo tee /etc/systemd/system/heartbeat.service >/dev/null <<'EOF'
[Unit]
Description=Demo heartbeat job
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/heartbeat.sh
EOF

sudo tee /etc/systemd/system/heartbeat.timer >/dev/null <<'EOF'
[Unit]
Description=Run heartbeat every minute

[Timer]
OnBootSec=30s
OnUnitActiveSec=1min
Unit=heartbeat.service

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now heartbeat.timer
sudo systemctl list-timers heartbeat.timer
journalctl -t heartbeat -f        # подожди минуту — увидишь записи
```

> **Почему timer, а не cron?** Таймеры systemd дают логирование, точные зависимости (`After=`), `OnBootSec` (запуск после загрузки), и единый интерфейс с остальными сервисами. cron жив, но для нового кода предпочитаем timer.

## Расширенная отработка

### Задача 1. Hardening sudoers под least privilege

Перепиши `/etc/sudoers.d/90-deploy` так, чтобы `deploy` без пароля мог делать **только** `systemctl restart heartbeat.timer` и `journalctl -u heartbeat`, а остальные команды — с паролем. Подсказка: `Cmnd_Alias`.

Проверка:

```bash
sudo -n systemctl restart heartbeat.timer   # ОК, без пароля
sudo -n apt update                           # должно спросить пароль
```

### Задача 2. Свой пользователь под сервис

Создай системного пользователя `heartbeat` (`useradd -r -s /usr/sbin/nologin heartbeat`), перепиши юнит, добавь `User=heartbeat`, `NoNewPrivileges=true`, `ProtectSystem=strict`, `ProtectHome=true`, `PrivateTmp=true`. Перезапусти, проверь, что в логах записи идут от пользователя `heartbeat`.

### Задача 3. Журнал поломки

Преднамеренно сломай sshd-конфиг (добавь строку `BrokenDirective yes` в drop-in). **Не делай reload.** Сначала запусти `sudo sshd -t` — он покажет ошибку. Удали строку. Это и есть «гигиена»: проверка перед применением.

## Acceptance criteria

- [ ] `ssh deploy@<VM>` работает по ключу, `password` запрещён.
- [ ] `ssh root@<VM>` — отказ.
- [ ] `sudo visudo -c` — без ошибок.
- [ ] `systemctl status heartbeat.timer` — active (waiting).
- [ ] `journalctl -t heartbeat --since "5 min ago"` — есть записи.
- [ ] (Расширенная) `sudo -n` работает только на whitelisted команды.

## Что обсудить на ревью

1. Зачем drop-in каталог `sshd_config.d/` — что будет, если апдейт пакета `openssh-server` перепишет `sshd_config`?
2. Почему таймер systemd чаще лучше cron в новом коде?
3. Что такое NOPASSWD-эскалация и почему её нельзя выдавать на ALL в проде?
4. Какие минимальные `Protect*` директивы ты бы поставил в unit-файл сервиса, обрабатывающего внешние запросы?

## Грабли

| Симптом | Причина | Лечение |
|---------|---------|---------|
| `Permission denied (publickey)` | права 0644 на `authorized_keys` | `chmod 0600 ~/.ssh/authorized_keys && chown $USER: ~/.ssh/authorized_keys` |
| `sshd` не подхватил конфиг | забыл `reload` | `sshd -t && systemctl reload ssh` |
| `sudo -n` просит пароль | файл `sudoers.d/*` имеет права не `0440` | `chmod 0440 /etc/sudoers.d/*` |
| Юнит не виден | `daemon-reload` не вызван | `systemctl daemon-reload` |
| Таймер не стреляет | забыли `enable --now` | `systemctl enable --now <name>.timer` |
