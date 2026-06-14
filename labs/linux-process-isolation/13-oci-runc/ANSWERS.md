# 13 — OCI и runc: контрольные вопросы

**Что такое OCI-bundle и зачем нужен стандарт OCI?**
Bundle = каталог `rootfs/` (ФС контейнера) + `config.json` (OCI runtime-spec:
процесс, namespaces, cgroups, caps, mounts, seccomp). OCI (Open Container
Initiative) стандартизировал image-spec и runtime-spec, чтобы любые инструменты
(Docker, podman, containerd, runc, crun) работали с контейнерами одинаково.

**Что описывает `config.json`?**
Декларативно — всё про контейнер: `process` (args, env, terminal, capabilities),
`linux.namespaces` (pid/net/ipc/uts/mount/cgroup), `linux.resources` (cgroup-лимиты),
`mounts` (/proc, /sys, /dev), `linux.seccomp`. То, что мы 9 этапов собирали руками.

**Где runc в цепочке `docker run`?**
`docker run` → dockerd → **containerd** (образы, жизненный цикл) →
**containerd-shim** (держит контейнер) → **runc** (создаёт контейнер из bundle,
применяет config.json, запускает процесс и выходит). runc — исполнитель,
containerd — менеджер.

**Зачем `process.terminal=false` при неинтерактивном запуске?**
При `terminal=true` runc пытается открыть `/dev/tty` и настроить псевдотерминал.
Без интерактивного tty (в скрипте/CI) это падает `open /dev/tty: no such device`.
Для неинтерактивного запуска ставят `terminal=false` (stdout процесса идёт в
stdout runc).

**Чем `runc` отличается от нашего `mycontainer.sh` (этап 11)?**
То же самое (namespaces + cgroups + pivot_root + caps + seccomp), но:
декларативно (`config.json` вместо ~150 строк bash), на Си, по стандарту OCI,
с полным жизненным циклом и seccomp/caps «правильно» через syscalls. `mycontainer`
доказывает, что магии нет; `runc` — как это делают в проде.
