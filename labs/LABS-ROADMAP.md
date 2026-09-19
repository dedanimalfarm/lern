# Roadmap лаб монорепо (кроме `kubernetes/`)

Снимок на 2026-09-19 по обходу репозитория. План расширения самого курса Kubernetes —
в [`kubernetes/docs/ROADMAP.md`](./kubernetes/docs/ROADMAP.md) (раздел «План большого
расширения»). Здесь — что делать с остальными лабами, чтобы они дотянулись до того же
стандарта, и в каком порядке.

## Где что стоит

| Лаба | Объём | Формат k8s-стандарта | Автопроверка | CI | Последняя правка |
|---|---|---|---|---|---|
| `docker` | 17 глав + challenges, capstone | частично (`lab/`, `broken/`, `checks/`) | 48 check-файлов | **сломан**: workflow фильтрует `docker-lab/**` — старый путь до переезда 2026-05-19; последние запуски — май, оба красные | 2026-06-17 |
| `linux-process-isolation` | 15 этапов (00–14) | **да** (эталон `01-chroot`) | 32 verify, 42 tasks/broken | нет workflow | 2026-06-24 |
| `api` | 8 модулей + Helpdesk-стенд | **да** | 19 verify, 24 tasks/broken | `api-labs-lint.yml` | 2026-06-17 |
| `linux-basics` | 6 разделов (~14 лаб) | нет (`tasks/broken` — 0) | 13 проверок | нет | 2026-07-18 |
| `linux-troubleshooting` | 12 модулей (USE-методология) | нет (`broken` — 0) | 14 проверок | нет | 2026-06-22 |
| `ansible` | 20 лаб старой нумерации (`1.easy-playbook` …) | нет | 2 проверки | нет | 2026-06-22 |
| `postgresql` | 9 модулей (standalone + production track) | частично | 9 проверок, 14 tasks/broken | нет | 2026-06-12 |
| `sql-basics` | 8+ модулей на Pagila (compose) | частично | 8 проверок, 16 tasks | нет | 2026-06-16 |
| `devops-junior-screening` | 13 лаб + FINAL-TEST | частично (acceptance criteria) | 4 проверки | нет | 2026-06-22 |
| `linux-memory` / `linux-cgroups` / `linux-processes` | 3 / 3 / 2 лабы | нет | 4 / 3 / 0 | нет | 2026-06 |
| `storage` | 1 лаба (6 модулей одним файлом) | нет | 0 | нет | 2026-05-23 |
| `helm` | 1 лаба | нет | 0 | нет | 2026-05-19 |
| `bash` | 2 (лаба + solutions) | нет | 1 | нет | 2026-06-22 |
| `git` | 3 лабы | нет | 0 | нет | 2026-05-19 |

Что считается стандартом (из `kubernetes/CLAUDE.md`): README с TOC, строкой
«⏱ время · сложность · пререквизиты» и теорией перед каждой частью; схемы — mermaid или
таблицы; `tasks/` с «Ожидаемый результат»; `broken/scenario-XX/` + `solutions/`;
`verify/{prepare,verify,cleanup}.sh` с контрактом `[OK]/[FAIL]`; `scripts/qa/run-module.sh`
и lint в CI с path-фильтром; «ожидаемые выводы» сняты с живого стенда.

## P0 — чинить сейчас (≈2 дня)

| # | Что | Почему |
|---|---|---|
| P0.1 | `.github/workflows/docker-lab-ci.yml` и `docker-lab-13-build-push.yml`: заменить `docker-lab/**` на `labs/docker/**` в `paths` и `working-directory`, пути `dockerfile:` | CI Docker-лабы не запускался с мая — любые правки идут без проверки |
| P0.2 | `labs/README.md`: счётчики (`kubernetes` — 28 модулей + 5 проектов, `linux-process-isolation` — 15 этапов и т.д.), ссылка на этот roadmap | индекс врёт |
| P0.3 | Общая QA-обвязка: вынести `kubernetes/scripts/verify/helpers.sh` (`ok/warn/fail`, `need_bin`, `require_*`) и `add-toc`-логику в `labs/_shared/`, лабы подключают по относительному пути | сейчас каждая лаба изобретает свой `[OK]/[FAIL]` |
| P0.4 | Reusable workflow `labs-lint.yml` (yamllint + shellcheck + markdown-links + mermaid-parse) с `workflow_call`; каждая лаба — тонкий workflow с path-фильтром | один линтер на всех, а не пять копий |

## P1 — Linux-фундамент (≈4 недели)

Это пререквизит для Docker и Kubernetes, и именно здесь меньше всего практики
по стандарту.

| Лаба | Что сделать | Стенд |
|---|---|---|
| `linux-troubleshooting` | По природе broken-first: каждый из 12 модулей = `broken/setup.sh` (ломает VM: съедает диск удалённым файлом, роняет unit, уводит время, засоряет conntrack), `triage/` с деревом «симптом → команда», `verify/` проверяет починку. Объединить пересечения с `devops-junior-screening/01–02`. Добавить `10-dns`, `11-oom`, `12-time-sync` в README-индекс (есть в дереве, нет в оглавлении). | GCE test-host (`root@34.27.14.145`) для host-only; `docker run --privileged` там, где хватает |
| `linux-basics` | Привести 6 разделов к стандарту: `tasks/` с ожидаемым результатом, по одному `broken/` на раздел, `verify/` (то, что делалось «живым прогоном в контейнере» для лабы 14, — в скрипты). Learning path «терминал → boot → диски → сеть → ресурсы» с ⏱. | контейнер ubuntu (CI) + VM для boot/дисков |
| `linux-memory` + `linux-cgroups` + `linux-processes` | Слить в трек **`linux-internals`** (memory → cgroups v2 → processes) с единым форматом и `run-all`; host-only пометки как в `linux-process-isolation`; связать с `linux-process-isolation/04-cgroups-v2` и k8s m12/m29 (resize, QoS). | VM/GCE |
| `linux-process-isolation` | Формат готов. Добавить CI (lint + verify с `HOST_ONLY=warn` в контейнере), learning path, мост в `docker/16` и k8s m14/m29 (user namespaces, seccomp — то, что потом станет `hostUsers: false` и `seccompProfile`). | есть |

## P2 — Контейнеры и автоматизация (≈5 недель)

| Лаба | Что сделать |
|---|---|
| `docker` | После P0.1: sweep всех `checks/` в CI; ASCII-схемы → mermaid (проверить, как в k8s); ⏱ и learning path; «ожидаемые выводы» со стенда; capstone (`12-capstone-projects`) с verify и критериями приёмки по образцу k8s project-d; `16-docker-to-kubernetes` как мост в k8s m01 (одинаковые образы/имена). |
| `ansible` | Реструктуризация 20 старых лаб в `modules/01..12` (inventory → vars/facts → handlers → roles → collections → vault → dynamic inventory → molecule → ansible-lint → docker-сценарии → сложные сценарии → capstone); стенд — контейнеры как managed-хосты (уже есть в лабах 13–16); verify через `ansible-playbook --check`/molecule; CI с `ansible-lint`. Объединить с `devops-junior-screening/03`. |
| `helm` | Одна лаба устарела рядом с k8s m09/m25. Либо удалить, либо расширить до 5 модулей (chart authoring и `_helpers.tpl`, values/схема, hooks и `helm test`, `chart-testing`/`ct lint`, OCI-registry и подпись чарта) — рекомендация: расширить, авторство чартов в m09 поверхностно; стенд — локальный k3s. |
| `storage` | Разбить 6 модулей на каталоги с `verify/` на loop-устройствах (`losetup`, mdadm/LVM на файлах) — гоняется в `docker --privileged` или VM; связать с k8s m05 (local-path, что под капотом). |
| `bash`, `git` | Довести до 6–8 модулей каждый с verify (bash — `bats`; git — проверка состояния репо скриптом); либо влить `bash` в `linux-basics/1.live-in-terminal`. Низкий приоритет. |

## P3 — Данные и API (≈3 недели)

| Лаба | Что сделать |
|---|---|
| `postgresql` | verify-контракт и CI на `docker run postgres`; production track: Patroni/repmgr HA, PgBouncer, мониторинг; «одна БД, два мира» — связь с k8s m21 (CloudNativePG). |
| `sql-basics` | CI: `docker compose` + Pagila + psql-assertions задач; ответы к задачам в `<details>`; финальный проект-отчёт. |
| `api` | Уже по стандарту. Расширение: GraphQL и gRPC модуль, вебхуки с подписью (HMAC), OAuth2 device flow, rate-limit/idempotency-key; interview Q&A (`INTERVIEW_QA.md` уже начат в `linux-basics/networking` — тот же формат). |
| `devops-junior-screening` | verify на каждую лабу; экзамен-режим FINAL-TEST с таймером и случайным вариантом (по образцу k8s `project-c/chaos`); связать с `linux-troubleshooting` и `ansible`. |

## Уровень монорепо

- Сквозной learning path: Linux (`linux-basics` → `linux-internals` → `linux-troubleshooting`)
  → контейнеры (`linux-process-isolation` → `docker`) → оркестрация (`kubernetes`) →
  данные (`sql-basics` → `postgresql`) → интеграции (`api`) → автоматизация (`ansible`,
  `git`, `bash`); `devops-junior-screening` как контрольная точка после Linux+Ansible.
- Один шаблон `CLAUDE.md` на лабу (стенд, правила контента, QA-контракт, грабли) — сейчас
  есть только у `kubernetes` и `api`.
- Единый DoD для модуля любой лабы (как в k8s ROADMAP): формат, задачи с ожидаемым
  результатом, ≥1 broken, поведенческий verify, зелёный CI, выводы со стенда.

## Порядок

P0 (2 дня) → P1 (4 нед) → P2 (5 нед) → P3 (3 нед). Параллелить можно P1 и P3 — разные
стенды. Каждый пункт заканчивается зелёным CI своей лабы и обновлением `labs/README.md`.
