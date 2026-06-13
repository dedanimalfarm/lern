# Сценарий 01: профиль загружен, но «не блокирует» — он в complain mode

## Симптом
Профиль на месте (`aa-status` его показывает), но запись в `/var/log` проходит,
хотя в профиле её нет.
```bash
sudo ./broken/scenario-01/make-broken.sh
# профиль в COMPLAIN — запись в /var/log НЕ блокируется (только логируется):
# WRITE_VARLOG: OK
```

> ⚠️ Только на хосте с AppArmor (на WSL2 скрипт сам сообщит, что LSM не активен).

## Подсказки
1. Посмотри режим: `aa-status | grep -A1 secret-reader` или раздел «complain mode».
2. Чем complain отличается от enforce для **неявно** запрещённых операций?
3. Запись в `/var/log` — это явный `deny` или неявный запрет (нет правила allow)?

## Диагностика
Профиль загружен, но в **complain**-режиме. В complain AppArmor не блокирует
**неявные** запреты (операции, на которые нет ни `allow`, ни `deny`-правила) — он
их только логирует (`apparmor="ALLOWED"`). Запись в `/var/log` именно такая: в
профиле нет `/var/log/** w`, но нет и явного `deny`. Поэтому в complain она
проходит (`WRITE_VARLOG: OK`), а в enforce — блокируется. (Чтение `/etc/passwd`
осталось бы `DENIED` и в complain — там есть явный `deny`.)

## Решение
Перевести профиль в enforce (см. `solutions/01-enforce-mode/fix.sh`):
```bash
sudo ./solutions/01-enforce-mode/fix.sh
# профиль в ENFORCE — запись в /var/log заблокирована:
# WRITE_VARLOG: DENIED
```

## Профилактика
- В проде профили должны быть в **enforce**. Проверяй: `aa-status` показывает,
  сколько профилей в enforce и сколько в complain.
- complain — только для этапа внедрения (собрать правила через `aa-logprof`),
  после чего обязательно `aa-enforce`.
- Не путай: complain ослабляет лишь неявные запреты; явные `deny` действуют всегда.
