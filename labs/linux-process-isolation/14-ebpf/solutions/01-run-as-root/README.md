# Решение scenario-01: запускать от root (CAP_BPF/CAP_SYS_ADMIN)

Загрузка eBPF-программ и чтение kernel-памяти требуют привилегий. bpftrace
отказывается работать не от root:

```bash
sudo bpftrace -e 'BEGIN { printf("ebpf ok\n"); exit(); }'   # от root — работает
```

```bash
sudo 14-ebpf/broken/scenario-01/make-broken.sh    # от nobody → ошибка про root
sudo 14-ebpf/solutions/01-run-as-root/fix.sh        # от root → ebpf ok
```

На свежих ядрах есть более узкий `CAP_BPF` (вместо полного `CAP_SYS_ADMIN`) — им
можно дать процессу право грузить eBPF без всех прав root. В контейнерных стеках
eBPF-агент (Falco/Tetragon) запускают на ХОСТЕ с привилегиями, не внутри контейнеров.
