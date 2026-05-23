# Глоссарий

Короткие определения терминов из вакансии и сборника. Без академизма — то, как стоит ответить на собеседовании за 30 секунд.

## A

**ADR (Architecture Decision Record)** — короткий документ (1–2 страницы), фиксирующий принятое архитектурное решение и его обоснование. Контекст → решение → альтернативы → последствия. См. [12](./12-documentation/).

**Ansible** — agentless система автоматизации конфигурации; код в YAML-плейбуках, доставляется по SSH. Ключевая концепция — **идемпотентность**.

**AppRole** — машинный auth-method в Vault: `role_id` (идентификатор) + `secret_id` (короткоживущий секрет) → token. См. [07](./07-secrets-vault/).

**ARC (Adaptive Replacement Cache)** — RAM-кеш ZFS. По умолчанию до 50% RAM хоста.

## B

**Bind-mount** — проброс пути хоста внутрь Docker-контейнера. `-v /host:/container`. Альтернатива — **volume** (Docker-managed).

**Blameless postmortem** — разбор инцидента, в котором обсуждают **процесс**, а не конкретного человека. См. [12](./12-documentation/).

**Bridge (Linux)** — программный L2-свитч в ядре. На нём «висят» физические NIC и виртуальные интерфейсы (tap/veth).

## C

**cAdvisor** — экспортёр метрик per-container от Google. Показывает CPU/RAM/IO каждого контейнера.

**Cardinality (high-cardinality labels)** — число уникальных значений label'а. Высокая cardinality (request_id, user_id) ломает Prometheus и Loki — растёт индекс. Никогда не клади в labels уникальные ID.

**cgroups (v2)** — механизм ядра для ограничения ресурсов (CPU, memory, IO) процессам. Используется systemd, Docker, Kubernetes.

**Cloud-init** — система первоначальной настройки cloud-VM (создание пользователя, ssh-ключ, hostname). На EC2/Azure уже включена.

**Conventional Commits** — соглашение для commit-сообщений: `<type>(<scope>): <subject>`. Типы: feat, fix, chore, docs, refactor, test.

**CoW (Copy-on-Write)** — модель ФС, где запись изменяет блоки на новые, а старые остаются жить (для снапшотов/откатов). ZFS, btrfs, overlay2.

## D

**Datacenter / colocation** — арендуемая стойка/юниты в чужом ДЦ. Сетевая связность, питание, охлаждение — провайдер; железо — твоё.

**DKMS (Dynamic Kernel Module Support)** — система пересборки модулей ядра (ZFS, VirtualBox) при апгрейде ядра. Боль и спасение одновременно.

**Docker** — контейнерный runtime (containerd → runc) + CLI/UX. Контейнер = процесс хоста, изолированный namespaces.

**DR (Disaster Recovery)** — план восстановления при катастрофе. Главные числа — **RPO** (Recovery Point Objective: сколько данных потеряем) и **RTO** (Recovery Time Objective: за сколько восстановимся).

**Drop-in** — файл в каталоге `*.d/` (например, `/etc/sshd_config.d/99-hardening.conf`), который читается основным демоном/менеджером в дополнение к главному конфигу. Атомарно, безопасно, не конфликтует с пакетами.

## E

**EBS** — Elastic Block Storage в AWS. Блочный диск для EC2.

**EC2** — Elastic Compute Cloud в AWS. Виртуальные машины.

**EIP (Elastic IP)** — фиксированный публичный IP в AWS. Без него после stop/start IP инстанса меняется.

**Exporter** — маленький демон, торчащий метрики в формате Prometheus (`/metrics`). `node_exporter`, `cadvisor`, `blackbox_exporter`.

## F

**Forwarding (IP forwarding)** — `net.ipv4.ip_forward=1` — разрешает ядру пересылать пакеты с одного интерфейса на другой. Нужно для NAT, VPN, контейнерных сетей.

## G

**Grafana** — UI для дашбордов поверх Prometheus, Loki, Postgres и др. datasource'ов.

## H

**HCL (HashiCorp Configuration Language)** — DSL HashiCorp. Используется в Terraform, Vault policy, Nomad.

**HSM (Hardware Security Module)** — устройство для хранения ключей. Используется как root-of-trust для Vault unseal и т. п.

## I

**Idempotency (Идемпотентность)** — свойство операции «применил один раз = применил сто раз = одно и то же конечное состояние». В Ansible — must-have для любой задачи.

**Immutable backup** — бэкап, который нельзя удалить раньше срока даже с правами root (S3 Object Lock compliance, WORM, append-only). Защита от ransomware и человеческой ошибки.

**Inventory (Ansible)** — список хостов и их параметров. INI/YAML/dynamic.

## J

**Journalctl / journald** — журналирование systemd, бинарный формат, теги по unit/priority/transport.

## K

**KMS (Key Management Service)** — облачный сервис управления криптоключами (AWS KMS, GCP KMS, Azure Key Vault).

**KV (Key-Value secrets engine, Vault)** — простое хранилище секретов. v1 — без версий, v2 — с версионированием и soft-delete.

**KVM (Kernel-based Virtual Machine)** — гипервизор в ядре Linux. Использует `qemu` как user-space обёртку, управляется через `libvirt`/`virsh`.

## L

**Lease (Vault)** — TTL для выданного токена/секрета. После expire — недействителен. Можно `renew` или `revoke` явно.

**Least privilege** — принцип: давать минимально достаточные права. Если сервис только читает — даём readonly, не admin.

**Libvirt** — высокоуровневая обёртка над KVM/QEMU/Xen/LXC. CLI — `virsh`.

**Loki** — TSDB-логи от Grafana. Индексирует только labels, тело — в chunks. Дешёвый, быстрый для тейлинга стримов.

**LPM (Longest Prefix Match)** — алгоритм выбора маршрута. Более специфичный (длинная маска) выигрывает.

**LVM (Logical Volume Manager)** — менеджер блочных устройств в Linux: PV → VG → LV. Альтернатива ZFS на классических ФС.

## M

**MASQUERADE** — частный случай SNAT, где outbound source IP подменяется на адрес исходящего интерфейса (без явного указания target). `iptables -t nat -A POSTROUTING -o ens5 -j MASQUERADE`.

**Multipass** — Canonical-инструмент для запуска Ubuntu-VM на локальной машине (Mac/Win/Linux), внутри использует hypervisor хоста.

**MTTD/MTTR** — Mean Time To Detect / Mean Time To Recover. Метрики операционной зрелости.

## N

**Namespaces (Linux)** — механизм изоляции в ядре: pid, net, mnt, ipc, uts, user, cgroup. База контейнеров.

**Netplan** — декларативный YAML-конфиг сети в Ubuntu. Рендерит конфиги для `systemd-networkd` или `NetworkManager`.

**netfilter / nftables / iptables** — стек фильтрации пакетов в ядре. iptables — старый интерфейс, nftables — новый.

**node_exporter** — Prometheus exporter для host-метрик (CPU, RAM, диск, NIC).

**NOPASSWD** — sudo без пароля. На cloud-image — норма; на проде — точечно через `Cmnd_Alias`.

## O

**Object Lock (S3)** — режим бакета, при котором объекты нельзя удалить раньше срока. Compliance > Governance > none.

**OOM (Out-Of-Memory killer)** — компонент ядра, который убивает процессы при нехватке памяти. Часто — Docker-контейнеры с слабым limit'ом.

**OpenSearch / Elasticsearch** — full-text search-движок для логов. Альтернатива Loki, дороже по железу, мощнее по поиску.

**Overlay2** — Docker storage driver: union FS поверх ext4. Слои образов = read-only, контейнер = top read-write layer.

## P

**Persistent keepalive (WireGuard)** — отправка холостого пакета каждые N секунд, чтобы NAT-роутер не закрыл сессию. 25 секунд — типичное значение.

**Playbook (Ansible)** — YAML с последовательностью плеев/задач для группы хостов.

**Postmortem** — отчёт об инциденте: timeline + root cause + action items. Blameless.

**Prometheus** — TSDB + pull-scraper. Опрашивает exporters раз в `scrape_interval`, хранит time-series локально.

**PromQL** — язык запросов Prometheus. `rate`, `irate`, `sum by`, `histogram_quantile`.

**Promtail** — log-агент Grafana под Loki. Сейчас рекомендуется `grafana/alloy` как преемник.

## R

**RAID (mirror/raidz/raidz2)** — топологии vdev в ZFS. mirror = RAID-1, raidz1 = RAID-5, raidz2 = RAID-6.

**rebase vs merge** — две стратегии интеграции веток. Rebase переписывает историю (делает линейной), merge сохраняет (с merge-commit).

**Resilver (ZFS)** — пересинхронизация диска в pool после замены/восстановления. Аналог rebuild в RAID.

**restic** — open-source backup tool на Go: content-addressed, шифрованный, дедуп, инкременты.

**RUNBOOK** — оперативная инструкция «алёрт → действия». Должен помещаться на экран. См. [12](./12-documentation/).

## S

**Sealed/Unsealed (Vault)** — состояния Vault. Sealed: данные в storage, но мастер-ключ не загружен. Unsealed: ключ собран из shards, сервер обслуживает.

**Secret engine (Vault)** — модуль, который хранит или **генерирует** секреты: kv, database, pki, transit, aws.

**Secrets sprawl** — расползание секретов по разным местам (env, .env-файлы, CI/CD vars, репы). Лечится централизацией (Vault) и аудитом.

**SLO/SLI/SLA** — уровень сервиса: SLI (что меряем), SLO (внутренняя цель), SLA (контракт с клиентом + штрафы).

**Snapshot** — моментальный снимок состояния (ZFS dataset, restic backup, EBS). Дёшев в CoW-системах.

**SNAT (Source NAT)** — подмена source-IP исходящих пакетов. Частный случай — **MASQUERADE**.

**Squash merge** — стратегия мерджа в GitHub: все коммиты feature-ветки склеиваются в один при merge в main.

**SSH ProxyJump** — `-J host1` — прыжок через bastion. Конфиг: `ProxyJump bastion` в `~/.ssh/config`.

**systemd** — init и менеджер сервисов в Linux. Юниты: `.service`, `.timer`, `.mount`, `.target`.

## T

**TSDB (Time-Series Database)** — БД для time-series данных (Prometheus, InfluxDB, VictoriaMetrics).

## U

**ufw (Uncomplicated Firewall)** — фронтенд над nftables/iptables. `ufw allow 22/tcp`.

**Unseal keys (Vault)** — Shamir-shards мастер-ключа. По умолчанию 5 шардов, нужно 3 для unseal.

## V

**Vault** — HashiCorp's secret management. Auth → policy → secret engine → secret. См. [07](./07-secrets-vault/).

**Vdev** — топологический элемент ZFS pool: disk, mirror, raidz, log, cache.

**Volume (Docker)** — managed-каталог в `/var/lib/docker/volumes/`. Лучше bind-mount для production-данных.

## W

**WireGuard** — современный VPN: UDP, stateless, в ядре Linux с 5.6. Конфиг — keypair + AllowedIPs. См. [10](./10-wireguard-vpn/).

## Z

**ZFS** — CoW-файловая система + volume manager + RAID + снапшоты + send/recv. Из Solaris, открыта (OpenZFS). См. [09](./09-zfs-snapshots/).

**ZTNA (Zero Trust Network Access)** — модель, в которой нет «доверенной внутренней сети»: каждое соединение аутентифицируется по identity. WireGuard + mTLS — частая реализация.
