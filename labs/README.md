# Лабораторные работы

Все учебные лабы из проекта, рассортированные по темам.

## Содержание

### Системы и Linux

| Папка | О чём | Кол-во |
|-------|-------|--------|
| [`linux-basics`](./linux-basics/) | Жизнь в терминале, boot, диски, сеть, ресурсы — стартовый блок | 8 разделов |
| [`linux-memory`](./linux-memory/) | Управление памятью: основы, лимиты cgroup v2, Transparent Hugepages (THP) | 3 лабы |
| [`linux-cgroups`](./linux-cgroups/) | cgroup v2: CPU, IO, Memory | 3 |
| [`linux-processes`](./linux-processes/) | Процессы: основы и стартовая лаба | 2 |
| [`linux-process-isolation`](./linux-process-isolation/) | Изоляция процессов: chroot, namespaces, cgroups, seccomp, AppArmor — путь к контейнерам | 15 этапов |
| [`linux-troubleshooting`](./linux-troubleshooting/) | Боевая диагностика: CPU/RAM, диски, сеть, логи, certs, strace, tcpdump, auditd, kernel tuning | 9 |
| [`storage`](./storage/) | Дисковая подсистема: разделы, ext4/xfs/btrfs, mdadm RAID, LVM, troubleshooting | 1 (6 модулей) |

### Контейнеры и оркестрация

| Папка | О чём | Кол-во |
|-------|-------|--------|
| [`docker`](./docker/) | Docker от основ до production: CLI, Dockerfile, compose, storage, networking, security, CI/CD, capstone | 17 глав |
| [`kubernetes`](./kubernetes/) | k8s: kubectl, pods, workloads, networking, storage, scheduling, security, observability, helm/gitops, kubeadm | 10 модулей + 3 проекта |
| [`helm`](./helm/) | Первая лаба по Helm 3 | 1 |

### Автоматизация

| Папка | О чём | Кол-во |
|-------|-------|--------|
| [`ansible`](./ansible/) | Ansible: playbooks, inventory, vars, debug, roles, molecule, docker-сценарии, статический анализ | 20 |
| [`bash`](./bash/) | Bash: циклы и условия (+ solutions) | 2 |
| [`git`](./git/) | Git: ветвление, серверная часть, инструменты | 3 |

### API и интеграции

| Папка | О чём | Кол-во |
|-------|-------|--------|
| [`api`](./api/) | Работа с API для L2-поддержки: HTTP/curl, JSON/jq, REST и чтение документации (OpenAPI), Postman, аутентификация (API key/Basic/JWT), вебхуки и боевые инциденты, capstone на Jira Service Management Cloud; свой учебный Helpdesk API (Python stdlib) с fault-injection | 7 модулей |
| [`devops-junior-screening`](./devops-junior-screening/) | Учебный сборник по вакансии Junior DevOps: Linux, сети, Ansible, observability, secrets, backup, WireGuard + финальное тестовое | 13 + FINAL-TEST |

## Откуда что приехало

| Новое расположение | Прежнее расположение |
|--------------------|----------------------|
| `labs/ansible/` | `ansible-lab/` |
| `labs/bash/` | `bash_scripts/labs/` |
| `labs/docker/` | `docker-lab/` |
| `labs/git/` | `git-lab-work/` |
| `labs/helm/` | `helm-lab/` |
| `labs/kubernetes/` | `k8s-new/k8s-labs/` |
| `labs/linux-basics/` | `linux-beginning/` |
| `labs/linux-cgroups/` | `lInux-lab-work/` |
| `labs/linux-memory/` | `linux/memory_management/labs/` |
| `labs/linux-process-isolation/` | `linux/process_isolation/` |
| `labs/linux-processes/` | `process/labs/` |
| `labs/linux-troubleshooting/` | `linux/troubleshooting_labs/` |
| `labs/storage/` | `disks/labs/` |

Перенос сделан через `git mv` — история файлов сохранена (`git log --follow <файл>`).

## Что НЕ перенесено

Эти каталоги остались на верхнем уровне — они не являются лабораторными в строгом смысле:

- `aegis-capstone/` — capstone-проект (Azure + Terraform + Ansible).
- `ansible-interview-questions/` — Q&A для собеседований.
- `k8s-new/k8s-interviews/`, `k8s-new/k8s-theory/` — теория и вопросы для собеса.
- `bash_scripts/level0..7/` — пошаговый трек заданий, не «labs».
- `process/{daemon,info,sighup,zombi_killer,*.sh}` — вспомогательные демо к курсу process.
- `cloud/azure/` — гайды и selfhosted-материалы, не лабы.
- `generate-logs/`, `la/`, `links/`, `way-to-SKA/`, `PROGRESS.md` — прочие материалы.
