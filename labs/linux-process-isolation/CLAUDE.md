# CLAUDE.md — linux-process-isolation

Учебный курс «изоляция процессов в Linux» (14 модулей): студент руками собирает
контейнер из примитивов ядра. Формат приведён к стандарту k8s-лаб этого репозитория
(`../kubernetes/CLAUDE.md`). Эталон — модуль **01-chroot**; модули 02–14 пока в
старом формате и приводятся к эталону по очереди (статус — в индексе README).

## Стенд

- Host-based bash-лаба: всё гоняется на самом хосте под `sudo`, кластер не нужен.
- Требования: Ubuntu/Debian, ядро ≥ 5.10, реальный root. Зависимости ставит
  `00-setup/install.sh` (busybox-static, util-linux, iproute2, libcap2-bin,
  apparmor-utils, systemd-container, debootstrap, stress-ng, strace …).
- Рабочие артефакты модулей живут в `/lab/<модуль>/…` (rootfs, маунты). Их
  всегда снимает `verify/cleanup.sh` (umount + rm), вызываемый trap'ом.
- ⚠️ Ограничения WSL2 (текущий хост разработки, ядро 6.6): AppArmor выключен
  (`/sys/module/apparmor/parameters/enabled` = N), нет `systemd-nspawn`,
  `debootstrap`, `bpftrace`. Значит модули **07/10/14** вживую не прогоняются —
  их «ожидаемые выводы» снимаются на полноценном Ubuntu-хосте и помечаются.
  Модули 01–06, 08, 09, 13 идут на WSL2 (cgroup v2, unshare, runc — на месте).

## Правила контента модулей

- Эталон формата — `01-chroot`. README обязан содержать: `## Оглавление` с
  маркерами `<!-- TOC -->` (генерится `scripts/qa/add-toc.sh`), строку
  `> ⏱ время · сложность · пререквизиты`, «Цель», `## Часть N` каждая с
  `### Теория для изучения перед частью` → шаги с **реальными** ожидаемыми
  выводами → `**Контрольные вопросы**`, затем `## Часть N: Troubleshooting`
  (дерево «симптом→причина» + ссылка на `broken/`), `## Проверка модуля`,
  `## Финальная карта ресурсов модуля`, `## Теоретические вопросы (итоговые)`,
  `## Практические задания (отработка)` (ссылки на `tasks/`), `## Шпаргалка`,
  `## Чему вы научились`, `## Уборка`.
- Layout модуля: `README.md`, `run.sh` (опц. демо), `ANSWERS.md`, `tasks/NN-*.md`
  (Задача/Проверка/Ожидаемый результат), `broken/scenario-NN/` (README
  Симптом→Решение + `make-broken.sh`), `solutions/NN-*/`, `verify/{prepare,
  verify,cleanup}.sh`.
- «Ожидаемые выводы» в README ОБЯЗАТЕЛЬНО снимаются с живого прогона на хосте, не
  из головы. Версии (busybox/ядро) и имена (hostname) пинятся и помечаются «у вас
  будут свои» — важна структура вывода. Где хост не тянет (07/10/14) — явная
  пометка «проверить на Ubuntu-хосте».

## QA-контракт

- `verify/verify.sh` сорсит `scripts/verify/helpers.sh` и использует его контракт:
  `ok`/`warn`/`fail` (печать `[OK]/[WARN]/[FAIL]`), `need_root`, `need_bin`,
  `require_file`, `assert_eq`/`assert_ne`, `require_succeeds`/`require_fails`,
  `ns_inode`. Под `set -e` идиома `<условие> || fail "<текст>"` валит прогон
  ровно на проваленной проверке.
- Прогон модуля: `scripts/qa/run-module.sh <NN-stage>` = `prepare.sh` →
  `verify.sh` → `cleanup.sh` (cleanup в trap EXIT — отрабатывает даже при падении
  verify или SIGTERM, иначе остаются примонтированные /proc,/sys,/dev и rootfs).
  Старый формат (есть `check.sh`, нет `verify/`) идёт через фолбэк на `check.sh`.
- `run-all.sh` — массовый прогон через `run-module.sh` (не падает на первом FAIL).
- Линт: `scripts/qa/lint.sh` (shellcheck `-x` по `scripts/` + `verify/broken/
  solutions` конвертированных модулей; markdown-дисциплина — TOC и ⏱-строка —
  только у модулей с `verify/verify.sh`). Гонять до коммита.

## Известные грабли (уже наступали)

- В `verify.sh` под `set -e` любая подстановка `$(chroot … )`/`$(… | grep …)`,
  которая может вернуть пусто/ненулевой код, обязана заканчиваться `|| true` —
  иначе скрипт молча умирает ДО строки с `fail` и QA падает без диагностики.
- `chroot $ROOT /bin/stat /proc/self/ns/*` требует примонтированного `/proc`
  ВНУТРИ rootfs — иначе «No such file or directory» (так смазался первый замер
  ns-inode: `prepare` снимает /proc в конце).
- Динамический бинарь (`/bin/bash`) в rootfs без `.so` даёт обманчивое
  «No such file or directory» (это `ENOENT` загрузчика, не самого бинаря) —
  отсюда выбор static busybox (см. `01-chroot/broken/scenario-01`).
- `rm -rf /lab/...` без предварительного `umount -R` псевдо-ФС может зацепить
  хостовые `/dev` через rbind — всегда сначала umount, потом rm.
- shellcheck: sourced-библиотека без shebang ловит SC2148 — лечится директивой
  `# shellcheck shell=bash`; функция, вызываемая только через `trap`, ловит
  SC2317 — лечится `# shellcheck disable=SC2317` над ней.

## Git/CI

- Коммиты: semantic + scope (`feat(linux-iso):`, `fix(m01):`), тело на русском,
  атомарные, с root-cause для багфиксов. Коммитить/пушить — только по явной
  просьбе пользователя.
- Git-корень — `/root/lern` (репо `dedanimalfarm/lern`, общее для нескольких
  лаб). После push проверять `gh run list` до зелёного.

## Статус раскатки

- ✅ `01-chroot` — переведён в стандарт (эталон), выводы сняты на WSL2, lint+verify зелёные.
- 🔸 `02–14` — старый формат, в очереди. Порядок раскатки: повторить структуру
  01 (README по шаблону + tasks/ + broken/scenario-01 + verify/{prepare,verify,
  cleanup}.sh поверх helpers.sh), снять реальные выводы (07/10/14 — на Ubuntu-хосте).
