# Сценарий 01: `bpftrace ... only supports running as the root user`

## Симптом
Запускаем bpftrace от обычного пользователя — и сразу отказ.
```bash
sudo ./broken/scenario-01/make-broken.sh
# (от nobody)
# ERROR: bpftrace currently only supports running as the root user.
```

> Host-only: нужен установленный `bpftrace` (на WSL2 скрипт сам сообщит).

## Подсказки
1. Какие привилегии нужны, чтобы загрузить eBPF-программу в ядро?
2. Кто их имеет — обычный пользователь или root?
3. Что общего у seccomp (этап 06) и eBPF по требованию привилегий?

## Диагностика
Загрузка eBPF-программ (`bpf()` syscall), прикрепление к tracepoints/kprobes и
чтение kernel-памяти требуют `CAP_BPF`/`CAP_SYS_ADMIN`. У непривилегированного
пользователя их нет, и bpftrace сразу отказывается работать: иначе любой
пользователь мог бы читать память ядра и события чужих процессов — это была бы
дыра в безопасности.

## Решение
Запускать через `sudo`/от root (см. `solutions/01-run-as-root/fix.sh`):
```bash
sudo ./solutions/01-run-as-root/fix.sh
# (от root) ebpf ok
```

## Профилактика
- Трассировку eBPF (bpftrace, bcc) запускай от root или дай процессу `CAP_BPF`
  (на свежих ядрах есть более узкий `CAP_BPF` вместо полного `CAP_SYS_ADMIN`).
- Для непривилегированного eBPF существуют ограниченные режимы, но bpftrace по
  умолчанию требует root.
- В контейнерах для наблюдения (Falco/Tetragon) eBPF-агент запускают на ХОСТЕ с
  привилегиями, а не внутри контейнеров.
