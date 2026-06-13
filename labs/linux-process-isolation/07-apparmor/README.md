# Лабораторная работа 07: AppArmor — мандатный контроль доступа (MAC)

## Оглавление
<!-- TOC -->
- [Предварительные требования](#-)
- [Стартовая проверка](#-)
- [Часть 1: MAC vs DAC и устройство AppArmor](#-1-mac-vs-dac---apparmor)
  - [Теория для изучения перед частью](#----)
  - [1.1 Посмотреть загруженные профили](#11---)
- [Часть 2: Профиль в enforce — блокировка даже для root](#-2---enforce-----root)
  - [Теория для изучения перед частью](#----)
  - [2.1 Запуск под enforce-профилем](#21---enforce-)
- [Часть 3: Режим complain и отладка](#-3--complain--)
  - [Теория для изучения перед частью](#----)
  - [3.1 complain vs enforce](#31-complain-vs-enforce)
- [Часть 4: Troubleshooting](#-4-troubleshooting)
  - [Теория: диагностика по симптому](#---)
  - [Инцидент 1: профиль в complain не блокирует](#-1---complain--)
- [Проверка модуля](#-)
- [Финальная карта ресурсов модуля](#---)
- [Теоретические вопросы (итоговые)](#--)
- [Практические задания (отработка)](#--)
- [Шпаргалка](#)
- [Чему вы научились](#--)
- [Уборка](#)
<!-- /TOC -->


> ⏱ время ~40 мин · сложность 4/5 · пререквизиты: 05-capabilities, базовые права файлов (DAC)

Цель: ограничить процесс политикой, которую он **не может обойти даже от root**.
Обычные права (DAC) задаёт владелец файла; **MAC** (Mandatory Access Control)
задаёт администратор профилем в ядре. **AppArmor** — path-based MAC в
Ubuntu/Debian/SUSE: профиль привязан к пути исполняемого файла и перечисляет, к
каким путям/возможностям программе можно. Загрузим профиль в enforce, увидим, как
процесс с `uid 0` получает `Permission denied` на запрещённый путь, и разберём
режим complain. Это `--security-opt apparmor=` у Docker.

> ⚠️ **Host-only модуль.** На WSL2 AppArmor выключен (`/sys/module/apparmor/
> parameters/enabled`=N, нет `/sys/kernel/security/apparmor`) — `verify/` там сам
> пропустит проверку (`[WARN]`, не падает). Все «ожидаемые выводы» сняты на реальном
> Ubuntu-хосте (GCP, AppArmor включён, 44 профиля). Развитие `05-capabilities`:
> там дробили права root, здесь — ограничиваем root политикой, которую он не снимет.

---

## Предварительные требования

```bash
sudo ./00-setup/check.sh              # apparmor_parser/aa-status — модуль 07 (apparmor-utils)
cat /sys/module/apparmor/parameters/enabled    # Y — AppArmor включён (на WSL2 будет N)
ls /sys/kernel/security/apparmor      # каталог есть → LSM активен
```

---

## Стартовая проверка

```bash
aa-status | head -3
# apparmor module is loaded.
# 44 profiles are loaded.
# 39 profiles are in enforce mode.
```

---

## Часть 1: MAC vs DAC и устройство AppArmor

### Теория для изучения перед частью

- **DAC** (rwx, владелец) защищает от *других пользователей*; root его игнорирует.
  **MAC** защищает даже от *скомпрометированного root-процесса*: политику задаёт
  админ, и программа не может её изменить, работая от uid 0.
- **AppArmor — path-based:** профиль `/etc/apparmor.d/...` привязан к пути бинаря и
  перечисляет разрешённые пути (`/path r`, `/path w`, `/path ix`…) и `capability`.
  Всё, что не разрешено, — **неявно запрещено**; есть и явные `deny` правила.
  (Альтернатива — SELinux, label-based, в RHEL/Fedora.)
- **Три режима:** `enforce` (нарушение блокируется + логируется), `complain`
  (только логируется — для отладки), `disabled` (выгружен).

---

### 1.1 Посмотреть загруженные профили

```bash
aa-status | head -3
cat /sys/kernel/security/apparmor/profiles | head -3   # сырой список профилей в ядре
```

**Контрольные вопросы:**
1. Чем MAC сильнее DAC и от чего именно он защищает?
2. К чему привязан профиль AppArmor (в отличие от SELinux-меток)?
3. Чем отличаются режимы enforce и complain?

---

## Часть 2: Профиль в enforce — блокировка даже для root

### Теория для изучения перед частью

- Профиль `profile.aa` привязан к `/usr/local/bin/secret-reader.sh`: явно
  запрещает `deny /etc/passwd r` и `deny /etc/shadow rw`, не разрешает запись в
  `/var/log` (неявный запрет), но разрешает `/tmp/** rw`. Загружается
  `apparmor_parser -r`.
- Когда скрипт запускается по своему пути, ядро **автоматически** применяет
  профиль (path-based). Дальше — `Permission denied` на запрещённое, несмотря на
  `uid 0`.

---

**Цель:** увидеть, что enforce-профиль блокирует root.

**Ресурсы:** `secret-reader.sh` (пробует читать /etc/passwd, писать в /var/log и /tmp),
`profile.aa` (политика).

---

### 2.1 Запуск под enforce-профилем

```bash
sudo install -m0755 ./07-apparmor/secret-reader.sh /usr/local/bin/secret-reader.sh
sudo cp ./07-apparmor/profile.aa /etc/apparmor.d/usr.local.bin.secret-reader.sh
sudo apparmor_parser -r /etc/apparmor.d/usr.local.bin.secret-reader.sh

# БЕЗ профиля (для сравнения) root может всё:
#   READ_PASSWD: OK / WRITE_VARLOG: OK / WRITE_TMP: OK

sudo /usr/local/bin/secret-reader.sh
# uid: 0
# READ_PASSWD: DENIED        <- /etc/passwd запрещён профилем (хоть мы root!)
# WRITE_VARLOG: DENIED       <- /var/log не разрешён → запись падает
# WRITE_TMP: OK              <- /tmp разрешён явно
```

```bash
# audit-лог подтверждает: отказ для процесса с fsuid=0 (root)
sudo journalctl -k | grep 'apparmor="DENIED".*secret-reader' | tail -1
# apparmor="DENIED" operation="mknod" profile="/usr/local/bin/secret-reader.sh"
#   name="/var/log/aa-test.log" ... requested_mask="c" denied_mask="c" fsuid=0 ouid=0
```

`fsuid=0` в логе — это и есть суть MAC: root запрещён политикой ядра.

**Контрольные вопросы:**
1. Почему `READ_PASSWD: DENIED`, хотя процесс работает от root?
2. Чем отличается «явный `deny`» от «неявного запрета» (не разрешено) в профиле?
3. Что в audit-логе доказывает, что заблокирован именно root-процесс?

---

## Часть 3: Режим complain и отладка

### Теория для изучения перед частью

- `aa-complain <путь>` переводит профиль в complain: **неявные** запреты больше не
  блокируются, только логируются (`apparmor="ALLOWED"`/audit). Это режим отладки:
  собрать, что программе реально нужно, через `aa-logprof`.
- **Важная тонкость:** явные `deny`-правила enforce-ятся **и в complain тоже**.
  Поэтому ниже `WRITE_VARLOG` (неявный запрет) станет `OK`, а `READ_PASSWD`
  (`deny /etc/passwd`) останется `DENIED`.

---

### 3.1 complain vs enforce

```bash
sudo aa-complain /usr/local/bin/secret-reader.sh
sudo /usr/local/bin/secret-reader.sh
# READ_PASSWD: DENIED        <- явный deny enforce-ится ВСЕГДА
# WRITE_VARLOG: OK           <- неявный запрет в complain НЕ блокируется (только лог)
# WRITE_TMP: OK

sudo aa-enforce /usr/local/bin/secret-reader.sh   # обратно в бой
sudo /usr/local/bin/secret-reader.sh
# WRITE_VARLOG: DENIED       <- снова блокируется
```

**Контрольные вопросы:**
1. Что меняет `aa-complain` для неявных запретов и для явных `deny`?
2. Зачем нужен complain при внедрении профиля на работающее приложение?
3. Каким инструментом достроить профиль по логам complain?

---

## Часть 4: Troubleshooting

### Теория: диагностика по симптому

```
Симптом
├─ профиль «не блокирует» неявный запрет ───────► он в complain-mode. aa-enforce
│     <путь>; проверь режим: aa-status | grep <профиль> (Сценарий 01)
├─ программа падает на старте под профилем ─────► не хватает #include
│     <abstractions/base> (libc/locale/…). Добавь abstractions/base в профиль
├─ профиль не применяется к бинарю ─────────────► путь в профиле ≠ реальный путь
│     exec (AppArmor path-based). Профиль крепится к ТОЧНОМУ пути
└─ apparmor_parser: Permission denied / в контейнере ─► нет CAP_MAC_ADMIN; профили
      грузятся на ХОСТЕ, не внутри контейнера
```

### Инцидент 1: профиль в complain не блокирует
Разобран в `broken/scenario-01/` (профиль загружен, но в complain — неявный запрет
`/var/log` пропускается). Воспроизвести и починить:
```bash
sudo ./broken/scenario-01/make-broken.sh        # complain → WRITE_VARLOG: OK (не блок)
sudo ./solutions/01-enforce-mode/fix.sh           # aa-enforce → WRITE_VARLOG: DENIED
```

---

## Проверка модуля

```bash
sudo ./scripts/qa/run-module.sh 07-apparmor
# --- module: 07-apparmor ---
# prepare...
# [OK] AppArmor активен; apparmor_parser на месте
# verify...
# [OK] MAC enforce: чтение /etc/passwd запрещено даже root (READ_PASSWD: DENIED)
# [OK] запись вне разрешённых путей запрещена (WRITE_VARLOG: DENIED)
# [OK] разрешённая операция работает (WRITE_TMP: OK)
# [OK] профиль secret-reader загружен (виден в /sys/kernel/security/apparmor/profiles)
# [OK] module 07-apparmor verified
```

На хосте без AppArmor (WSL2) `verify/` печатает `[WARN] ... host-only` и проходит
(skip), не ломая прогон. Полное демо (вкл. complain + dmesg) — `sudo ./run.sh`.

---

## Финальная карта ресурсов модуля

| Ресурс | Что это | Демонстрирует |
|--------|---------|---------------|
| `profile.aa` | AppArmor-профиль (path-based) | политику MAC на путь бинаря |
| `secret-reader.sh` | тест read/write по путям | OK/DENIED под профилем |
| `apparmor_parser -r` | загрузка профиля в ядро | применение политики |
| enforce vs complain | режимы профиля | блокировка vs только логи |
| `apparmor="DENIED" fsuid=0` | audit-лог | что заблокирован root |

---

## Теоретические вопросы (итоговые)
1. Чем MAC отличается от DAC и почему MAC защищает от скомпрометированного root?
2. AppArmor (path-based) vs SELinux (label-based) — ключевые отличия?
3. Три режима профиля; что именно меняет complain (и что НЕ меняет — явный `deny`)?
4. Зачем `#include <abstractions/base>` в профиле?
5. Почему профиль AppArmor нельзя сменить изнутри контейнера (что дропнуто)?

> Разбор ответов — в `ANSWERS.md`.

---

## Практические задания (отработка)

См. `tasks/`:
1. **`tasks/01-enforce-profile.md`** — загрузить профиль enforce, поймать `Permission denied` у root.
2. **`tasks/02-complain-mode.md`** — complain vs enforce, увидеть разницу для неявного запрета.
3. **`tasks/03-aa-status-logs.md`** — `aa-status`, audit-логи `apparmor="DENIED"`.

Дополнительно:
4. Убери `#include <abstractions/base>` из профиля и посмотри, как скрипт падает на старте.
5. Напиши профиль для `/usr/bin/curl`, разрешив только `https`-абстракцию, и поймай отказ на файл.

---

## Шпаргалка

```bash
# === загрузить/снять профиль ===
apparmor_parser -r /etc/apparmor.d/<profile>     # загрузить/обновить
apparmor_parser -R /etc/apparmor.d/<profile>     # выгрузить

# === режимы ===
aa-enforce /path/to/bin       # блокировать нарушения
aa-complain /path/to/bin      # только логировать (отладка)
aa-status                     # что загружено и в каком режиме

# === отладка ===
journalctl -k | grep 'apparmor="DENIED"'         # что заблокировано
aa-logprof                                        # достроить профиль по логам

# === Docker ===
# --security-opt apparmor=my-profile   (профиль заранее загружен на ХОСТЕ)
# --security-opt apparmor=unconfined   (снять — плохая идея)
```

---

## Чему вы научились
- Различать DAC и MAC и понимать, что MAC блокирует даже root.
- Загружать AppArmor-профиль (path-based) и видеть `Permission denied` у `uid 0`.
- Различать enforce/complain и тонкость: явный `deny` enforce-ится и в complain.
- Читать audit-логи `apparmor="DENIED"` и сопоставлять с `--security-opt apparmor`.

---

## Уборка

```bash
sudo ./verify/cleanup.sh
# [OK] cleanup 07-apparmor
```

> Дальше — `08-overlayfs`: слоистая файловая система (lower/upper/work, CoW,
> whiteout) — то, как Docker собирает образ из слоёв (`docker pull`/`commit`).
