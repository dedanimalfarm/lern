# Решение scenario-01: перевести профиль в enforce

complain ослабляет неявные запреты (только логирует). Для реальной защиты профиль
должен быть в enforce:

```bash
aa-enforce /usr/local/bin/secret-reader.sh     # или flags=(enforce) в профиле
aa-status | grep -A1 secret-reader             # проверить режим
```

```bash
sudo 07-apparmor/broken/scenario-01/make-broken.sh    # complain → WRITE_VARLOG: OK
sudo 07-apparmor/solutions/01-enforce-mode/fix.sh       # enforce → WRITE_VARLOG: DENIED
```

complain нужен только на этапе внедрения профиля (собрать правила через
`aa-logprof`). В проде — всегда enforce. Помни: явные `deny`-правила действуют в
обоих режимах, complain меняет поведение только для неявных запретов.
