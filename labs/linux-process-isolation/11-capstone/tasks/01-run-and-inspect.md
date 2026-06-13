# 01 — Запустить контейнер и увидеть изоляции

## Задача
Запустить `mycontainer.sh` и убедиться, что внутри изолированы PID (свой PID 1),
UTS (свой hostname), а корень — из alpine (overlay сработал).

## Проверка
```bash
sudo ./11-capstone/mycontainer.sh run alpine -- sh -c '
  echo "PID 1:   $(cat /proc/1/comm)"
  echo "hostname:$(hostname)"
  echo "uid:     $(id -u)"
  echo "os:      $(grep ^ID= /etc/os-release)"
  echo "procs:   $(ls -d /proc/[0-9]* | wc -l)"
'
```

## Ожидаемый результат
```
PID 1:   sh             # PID-ns: наш процесс это PID 1
hostname:mycontainer    # UTS-ns: свой hostname
uid:     0              # root внутри
os:      ID=alpine      # overlay из alpine rootfs
procs:   4              # PID-ns изолирован (единицы процессов, не сотни)
```
Один скрипт собрал overlay + cgroup + namespaces + pivot_root — то, что мы 10
этапов разбирали по отдельности. Это `docker run --rm alpine sh` на голых примитивах.
