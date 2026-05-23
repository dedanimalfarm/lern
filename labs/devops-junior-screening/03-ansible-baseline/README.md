# 03 · Ansible baseline

> Тема из вакансии: «Опыт с Ansible: playbooks, роли, inventory, понимание idempotency». Это автоматизация того, что вручную сделали в [01](../01-linux-baseline/) и [02](../02-networking-firewall/).

## Цель и навыки

Привести свежую Ubuntu 22.04/24.04 VM в состояние **«готова к продакшену начального уровня»** одним прогоном `ansible-playbook`. Повторный запуск должен дать `changed=0` — это и есть проверка идемпотентности, которую гарантированно спросят на интервью.

После лабы ты:

- понимаешь разницу между inventory / group_vars / host_vars и `defaults` роли;
- умеешь раскладывать роль по каноническим папкам (`tasks/`, `handlers/`, `templates/`, `defaults/`, `vars/`, `files/`, `meta/`);
- знаешь, почему `template + notify` идемпотентнее, чем `lineinfile`;
- умеешь читать `ansible-playbook -v / -vvv` и понимать, на каком шаге задача стала `changed`;
- знаешь два режима: `--check` (dry-run) и `--diff` (показ изменений в файлах).

## Теоретический минимум

**Inventory** — список хостов и их параметры. Может быть INI/YAML/динамический (скрипт). Группа `[lab]` объединяет хосты; `[lab:vars]` — переменные группы.

**Иерархия переменных** (от низкого к высокому приоритету, грубо): `role defaults` → `inventory vars` → `host_vars/` → `group_vars/` → `--extra-vars`. Полная таблица — в [официальной доке](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_variables.html#understanding-variable-precedence), и **она спрашивается на собесе**.

**Идемпотентность** — повторное применение не меняет состояние, если оно уже целевое. Модули типа `apt`, `template`, `user`, `service` — идемпотентны по сути. `command`/`shell` — **нет**, и требуют `creates:`/`changed_when:`/`when:` для приличия.

**Handlers** — задачи, которые срабатывают только если их кто-то `notify`'ит, и **только один раз за плей**. Используются для рестартов сервисов после изменения конфига.

**Tags** — позволяют запускать подмножество задач: `ansible-playbook site.yml --tags ssh`.

**Roles** — переиспользуемые единицы. Стандартная структура каталогов фиксирована (см. `ansible-galaxy init <name>`).

## Что должно быть после прогона

1. Создан служебный пользователь `deploy` с группой `sudo` и одним SSH-ключом.
2. SSH-демон ужесточён: запрещены `PasswordAuthentication` и логин `root`.
3. Установлен и включён `ufw` с минимальным набором: `22/tcp` разрешён, всё остальное — запрещено.
4. Поставлены базовые пакеты: `htop curl jq ca-certificates unattended-upgrades chrony`.
5. Включены автоматические security-обновления (`unattended-upgrades`).
6. Включён и синхронизирован NTP (`chrony`).
7. Установлен корректный hostname (берётся из inventory).

## Структура (которую тебе нужно собрать)

```
01-ansible-baseline/
├── ansible.cfg
├── inventory/hosts.ini
├── playbooks/site.yml
└── roles/common/
    ├── defaults/main.yml
    ├── tasks/main.yml
    ├── handlers/main.yml
    ├── templates/sshd_hardening.conf.j2
    └── files/...
```

Скелет уже создан в каталоге. README содержит **заготовки** — твоя задача дописать `tasks/main.yml` и `templates/sshd_hardening.conf.j2`, чтобы playbook проходил.

## Задание

### Шаг 1. inventory + ansible.cfg

`inventory/hosts.ini`:

```ini
[lab]
junior-lab ansible_host=<VM-IP> ansible_user=ubuntu

[lab:vars]
ansible_ssh_private_key_file=~/.ssh/vast
ansible_python_interpreter=/usr/bin/python3
```

`ansible.cfg`:

```ini
[defaults]
inventory      = inventory/hosts.ini
roles_path     = roles
host_key_checking = False
retry_files_enabled = False
stdout_callback = yaml
```

### Шаг 2. Роль `common`

Заготовка `roles/common/defaults/main.yml`:

```yaml
deploy_user: deploy
deploy_user_groups: [sudo]
deploy_user_authorized_key: "{{ lookup('file', lookup('env', 'HOME') + '/.ssh/vast.pub') }}"
common_packages:
  - htop
  - curl
  - jq
  - ca-certificates
  - unattended-upgrades
  - chrony
ssh_allow_password_auth: false
ssh_permit_root_login: "no"
firewall_allowed_tcp: [22]
```

`roles/common/tasks/main.yml` — реализуй минимум:

- `ansible.builtin.apt` — `update_cache: yes`, `cache_valid_time: 3600`, поставить `common_packages`.
- `ansible.builtin.user` — создать `deploy_user`, shell `/bin/bash`, добавить в `deploy_user_groups`.
- `ansible.posix.authorized_key` — положить ключ.
- `ansible.builtin.template` — sshd-конфиг, **уведомление** `restart sshd`.
- `community.general.ufw` — `default deny incoming`, разрешить порты из `firewall_allowed_tcp`, в конце `state: enabled`.
- `ansible.builtin.systemd` — `chrony` и `unattended-upgrades` `enabled=yes state=started`.
- `ansible.builtin.hostname` — взять из `inventory_hostname`.

`roles/common/handlers/main.yml`:

```yaml
- name: restart sshd
  ansible.builtin.systemd:
    name: ssh
    state: restarted
```

`roles/common/templates/sshd_hardening.conf.j2`:

```
# Managed by Ansible
PasswordAuthentication {{ 'yes' if ssh_allow_password_auth else 'no' }}
PermitRootLogin {{ ssh_permit_root_login }}
KbdInteractiveAuthentication no
```

Файл кладётся в `/etc/ssh/sshd_config.d/99-hardening.conf` — это **важно**: drop-in каталог уже включён `Include` в дефолтном sshd_config Ubuntu, и ты не ломаешь основной конфиг.

### Шаг 3. Playbook

`playbooks/site.yml`:

```yaml
---
- name: Baseline configuration
  hosts: lab
  become: true
  gather_facts: true
  roles:
    - common
```

### Шаг 4. Прогон и проверка

```bash
ansible-galaxy collection install community.general ansible.posix
ansible-playbook playbooks/site.yml                 # первый прогон
ansible-playbook playbooks/site.yml --check         # ожидаем changed=0
ansible-playbook playbooks/site.yml                 # повторный — тоже changed=0
```

После — переподключись новым пользователем:

```bash
ssh -i ~/.ssh/vast deploy@<VM-IP> 'sudo ufw status verbose; chronyc tracking | head -5'
```

## Acceptance criteria

- [ ] Повторный `ansible-playbook` показывает `changed=0`.
- [ ] `ssh ubuntu@<VM>` с паролем — запрещён, а с ключом — работает.
- [ ] `ssh deploy@<VM>` — работает, `sudo -n true` — успешно.
- [ ] `sudo ufw status` показывает `Status: active` и `22/tcp ALLOW`.
- [ ] `systemctl is-enabled chrony unattended-upgrades` — обе `enabled`.
- [ ] `cat /etc/hostname` совпадает с `inventory_hostname`.

## Что обсудить на ревью / собесе

1. Почему drop-in (`sshd_config.d/`), а не правка основного `sshd_config`? — атомарность, проще откатить, не конфликтует с пакетным обновлением.
2. Чем `apt cache_valid_time` лучше безусловного `update_cache`? — экономит сеть и время, идемпотентно по факту.
3. Где у тебя секреты в этой лабе и почему их не должно быть в git? — переход к [`07-secrets-vault`](../07-secrets-vault/).
4. Что сломается, если запустить playbook на уже работающем prod-сервере? — порядок задач: `ufw enable` **после** того, как разрешили 22; иначе сам себе обрубишь сессию.
5. Где у тебя получится **changed на каждом прогоне** при наивной реализации? — самые частые: `template` с CR/LF, `lineinfile` без `regexp:`, `command` без `creates:`.

## Расширенная отработка

### Задача 1. Группа host_vars

Сделай файл `inventory/host_vars/junior-lab.yml` с переменной `firewall_allowed_tcp: [22, 8080]`. Прогоняй playbook и убедись, что 8080 открылся, **не меняя дефолтов роли**. Это демонстрирует иерархию переменных вживую.

### Задача 2. Tags + check + diff

Запусти:

```bash
ansible-playbook playbooks/site.yml --tags ssh --check --diff
```

Поставь тэг `ssh` на нужные задачи (`authorized_key`, `template sshd_hardening`, handler `restart sshd`). Должен сработать только этот subset, изменений после первого прогона быть не должно.

### Задача 3. Vault-encrypted переменная

Создай `group_vars/lab/secrets.yml` через `ansible-vault create`. Положи туда фейковый пароль вида `db_password: changeme123`. Прогон: `ansible-playbook --ask-vault-pass`. Это разминка под полноценный [Vault](../07-secrets-vault/) и иллюстрация принципа «секреты в git только зашифрованные».

## Грабли

| Симптом | Причина | Лечение |
|---------|---------|---------|
| `changed=1` на втором прогоне у задачи `template` | в шаблоне CR/LF, на хосте LF | `dos2unix` в репе, `gitattributes text=auto` |
| `Module failed: timeout` на `apt update` | DNS пакеты не разрезолвились или прокси | проверь `resolvectl status` на VM |
| `Permission denied` при `become: true` | NOPASSWD не настроен | один раз руками, потом playbook'ом |
| `Connection unreachable` после ufw | `ufw enable` сработал до `allow 22` | переставь местами в роли, **сначала allow, потом enable** |
| `Failed to lock apt` | параллельный `unattended-upgrade` | дождись, или `systemctl stop unattended-upgrades` на время прогона |
