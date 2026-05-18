# Лабораторные работы: Базовый и Продвинутый Troubleshooting Linux

Этот набор лабораторных работ предназначен для отработки навыков диагностики и решения проблем в Linux-системах. Темы основаны на методологии USE (Utilization, Saturation, Errors).

## Требования к стенду
- **ОС:** Ubuntu 20.04/22.04 или Debian 11/12
- **Ресурсы:** Минимум 2 vCPU, 2 ГБ RAM
- **Утилиты:** `stress-ng`, `ncdu`, `lsof`, `curl`, `dnsutils`, `iptables`, `openssl`, `python3`, `strace`, `tcpdump`, `auditd`, `chrony` (или systemd-timesyncd)
- Количество машин: 1

## Структура курса

### Базовый блок (USE-методология)
1. `01-system-cpu-ram`: Поиск процессов, пожирающих процессор и память.
2. `02-disk-io`: Поиск "скрытых" удаленных файлов и утечек диска (`lsof +L1`).
3. `03-networking`: Диагностика недоступных сетевых сервисов и портов (`ss`, `iptables`).
4. `04-logs-services`: Анализ упавших systemd-сервисов (`journalctl`).
5. `05-certificates`: Базовая работа с SSL/TLS сертификатами (`openssl`).

### Продвинутый блок
6. `06-advanced-tracing`: Трассировка системных вызовов проблемных процессов (`strace`).
7. `07-network-traffic`: Анализ и сниффинг сетевого трафика (`tcpdump`).
8. `08-audit-users`: Аудит файловой системы и активности пользователей (`auditd`, `last`).
9. `09-kernel-tuning`: Работа с лимитами ядра (`sysctl`, `inotify`).

### Боевые сценарии production
10. `10-dns`: «Сеть работает, но хост не виден» — DNS, `/etc/hosts`, `nsswitch`, `resolvectl`.
11. `11-oom-memory`: OOM-killer и memory pressure — `dmesg`, `oom_score_adj`, `/proc/pressure`.
12. `12-time-sync`: Рассинхрон часов ломает TLS/JWT/Kerberos — `timedatectl`, `chronyc`.
13. `13-mounts`: `target is busy`, readonly remount, stale NFS — `fuser`, `lsof`, `umount -l`.
14. `14-ulimits-fd`: «Too many open files» — `ulimit`, `prlimit`, systemd `LimitNOFILE`.

Для каждого этапа есть скрипт `simulate.sh`, который ломает или нагружает систему, и `README.md` с инструкциями по решению. Где нужно — также есть `cleanup.sh` для отката.
