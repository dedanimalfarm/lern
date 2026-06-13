# Решение scenario-01: флаг `e` (effective) — `+ep`

Обычная (не cap-aware) программа не активирует привилегию из permitted сама.
Нужен флаг `e`, чтобы она была effective сразу после `execve`:

```bash
setcap cap_net_bind_service+ep ./bin     # вместо +p
getcap ./bin                             # ./bin cap_net_bind_service=ep
```

```bash
sudo 05-capabilities/broken/scenario-01/make-broken.sh    # +p → NOTBOUND
sudo 05-capabilities/solutions/01-effective-flag/fix.sh    # +ep → BOUND (на реальном хосте)
```

`+p` без `e` имеет смысл только для программ, которые сами поднимают привилегию
через `libcap`/`capset()` в нужный момент (минимизация окна с привилегией).
