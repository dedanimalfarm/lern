# Решение scenario-01: `prctl(PR_SET_NO_NEW_PRIVS)` перед фильтром

Непривилегированный процесс может поставить seccomp-фильтр только если он сначала
зафиксировал `no_new_privs`:

```c
prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0);              // обязательно для не-root
prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &prog);   // теперь разрешено
```

Настоящий `06-seccomp/seccomp_bpf.py` делает оба вызова — поэтому работает и у root,
и у `nobody`. Битый `seccomp_no_nnp.py` пропускает первый → у `nobody` `EACCES`.

```bash
sudo 06-seccomp/broken/scenario-01/make-broken.sh    # nobody без no_new_privs → errno 13
sudo 06-seccomp/solutions/01-no-new-privs/fix.sh       # nobody с no_new_privs → uname SIGSYS
```

От root фильтр ставится и без `no_new_privs` (через `CAP_SYS_ADMIN`), но привычка
ставить его делает код одинаковым для привилегированного и непривилегированного
запуска. Так поступают `runc`, Chrome, systemd.
