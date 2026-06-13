# Сценарий 01: не-root не может поставить seccomp-фильтр без `PR_SET_NO_NEW_PRIVS`

## Симптом
От `nobody` ставим seccomp-фильтр — и `prctl(PR_SET_SECCOMP)` падает с
`Permission denied`, хотя сам фильтр корректный.
```bash
sudo ./broken/scenario-01/make-broken.sh
# nobody ставит seccomp-фильтр БЕЗ PR_SET_NO_NEW_PRIVS:
# PR_SET_SECCOMP failed: errno=13 (Permission denied)
```

## Подсказки
1. Сравни `seccomp_no_nnp.py` с рабочим `06-seccomp/seccomp_bpf.py` — какого вызова не хватает?
2. От root этот же скрипт срабатывает. Что есть у root, чего нет у nobody?
3. Что гарантирует ядру `PR_SET_NO_NEW_PRIVS` и почему это важно для SUID-программ?

## Диагностика
Поставить seccomp-фильтр может либо процесс с `CAP_SYS_ADMIN` (root), либо любой
процесс, который **зафиксировал `no_new_privs`** через
`prctl(PR_SET_NO_NEW_PRIVS, 1)`. Без этого непривилегированный фильтр запрещён:
иначе пользователь мог бы навесить хитрый фильтр на SUID-бинарь и обойти его
логику. `seccomp_no_nnp.py` пропускает этот вызов → от `nobody` ядро отвечает
`EACCES` (errno 13). От root всё работает, потому что у него `CAP_SYS_ADMIN`.

## Решение
Выставить `no_new_privs` ПЕРЕД установкой фильтра — что и делает настоящий
`seccomp_bpf.py` (см. `solutions/01-no-new-privs/fix.sh`):
```bash
sudo ./solutions/01-no-new-privs/fix.sh
# nobody с PR_SET_NO_NEW_PRIVS — фильтр ставится, uname получает SIGSYS
```

## Профилактика
- Любой код, ставящий seccomp у не-root, обязан сначала
  `prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0)`. Так делают `runc`, Chrome, systemd.
- Помни: `no_new_privs` навсегда запрещает процессу и потомкам получать новые
  привилегии (SUID/file-caps перестают «повышать») — это часть модели, а не помеха.
- От root фильтр ставится и без него (через `CAP_SYS_ADMIN`), но привычка ставить
  `no_new_privs` делает код одинаковым для root и не-root.
