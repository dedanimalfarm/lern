# 03 — aa-status и audit-логи

## Задача
Научиться видеть загруженные профили и их режим (`aa-status`) и читать audit-логи
отказов AppArmor — там видно, что заблокирован именно root-процесс.

## Проверка
```bash
aa-status | head -3
aa-status | grep secret-reader
sudo journalctl -k | grep 'apparmor="DENIED".*secret-reader' | tail -1
```

## Ожидаемый результат
```
apparmor module is loaded.
44 profiles are loaded.
39 profiles are in enforce mode.
   /usr/local/bin/secret-reader.sh
apparmor="DENIED" operation="mknod" profile="/usr/local/bin/secret-reader.sh"
  name="/var/log/aa-test.log" ... requested_mask="c" denied_mask="c" fsuid=0 ouid=0
```
`fsuid=0` (и `ouid=0`) в записи DENIED — доказательство, что MAC заблокировал
процесс, работающий от root. Это ключевое отличие MAC от DAC.
