# Сценарий 01: `setcap +p` вместо `+ep` — привилегия есть, но не действует

## Симптом
Выдали бинарю `CAP_NET_BIND_SERVICE`, `getcap` подтверждает — а bind на :80 от
`nobody` всё равно отказывает.
```bash
sudo ./broken/scenario-01/make-broken.sh
# getcap: /tmp/lpi-pyweb cap_net_bind_service=p      <- привилегия НА МЕСТЕ
# nobody :80 (+p) → NOTBOUND                          <- но bind всё равно нельзя
```

> ⚠️ Само срабатывание bind проверяется на реальном Linux-хосте (на WSL2 file-cap
> bind не энфорсится). Суть же — в разнице флагов `+p` и `+ep`, видна на любом хосте
> через `getcap`.

## Подсказки
1. Сравни `getcap` тут (`=p`) с рабочим вариантом (`=ep`). Чем отличается?
2. Что значат буквы `e` и `p` в наборе file capability (см. теорию Части 1)?
3. Кто должен «включить» привилегию из permitted, если её нет в effective?

## Диагностика
`setcap cap_net_bind_service+p` положил привилегию в **permitted**, но НЕ в
**effective**. После `execve` ядро вычисляет effective-набор: для обычной (не
cap-aware) программы привилегия из permitted **сама не активируется** — программа
должна была бы вызвать `capset()`, чего `python` не делает. Итог: `getcap`
показывает `=p`, привилегия «есть», но в `CapEff` её нет → bind :80 запрещён.

## Решение
Дать флаг `e` (effective) вместе с `p` — `+ep` (см. `solutions/01-effective-flag/fix.sh`):
```bash
sudo ./solutions/01-effective-flag/fix.sh
# getcap: /tmp/lpi-pyweb cap_net_bind_service=ep
# nobody :80 (+ep) → BOUND
```

## Профилактика
- Для обычных программ всегда `setcap cap_x+ep` — `e` делает привилегию активной
  сразу после `execve`.
- `+p` (без `e`) имеет смысл только для cap-aware программ, которые сами поднимают
  привилегию через `libcap`/`capset()` в нужный момент (минимизация окна).
- Быстрая проверка: `getcap bin` должен показывать `=ep`, а не `=p`.
