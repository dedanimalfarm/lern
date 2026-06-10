# CLAUDE.md — k8s-labs

Учебный репозиторий Kubernetes-лабораторий (27 модулей + 5 capstone).
План развития: `docs/ROADMAP.md` (модули 26–28 — следующие на очереди).

## Стенд

- Кластер: Kubespray на 3× GCE VM (проект `k8s-lab-test-352440`,
  us-central1-a), k8s v1.36.x + Calico. IaC: `cluster-kubespray/` (Terraform),
  inventory: `/root/kubespray/inventory/labcluster/`.
- `export KUBECONFIG=/root/.kube/kubespray.conf` — для ВСЕХ kubectl-команд.
- Жизненный цикл — только через `scripts/cluster/`:
  `up.sh [--stacks|--addons]` (полный подъём ~25 мин; `--addons` =
  + ВСЕ persistent-аддоны — для полного восстановления стенда), `start.sh`
  (после остановки; сам обновляет IP в state/inventory/kubeconfig),
  `stop.sh`, `down.sh`.
- VM сами стопятся в 22:00 (+04) — resource policy `lab-autostop`.
  После любого stop/start внешние IP МЕНЯЮТСЯ → поднимать только `start.sh`.
- Стеки наблюдаемости: kube-prometheus-stack `kps` в ns `monitoring` (helm),
  Loki/Promtail — манифесты модуля 18 в ns `lab`. Пароль Grafana — в secret
  `kps-grafana`; порт-форвардить на свободный порт (3000 на хосте занят).

## Правила контента модулей

- Эталон формата — `modules/29-*` и `modules/30-*`: README c TOC
  (`scripts/qa/add-toc.sh`, пропускает файлы с маркером `<!-- TOC -->`),
  строка «⏱ время · сложность · пререквизиты», теория перед каждой частью,
  `tasks/*.md`, `broken/scenario-XX/` + `solutions/`,
  `verify/{prepare.sh,verify.sh,cleanup.sh}`.
- «Ожидаемые выводы» в README ОБЯЗАТЕЛЬНО снимаются с живого кластера —
  не из головы. Версии образов пиновать и фиксировать в README.
- Бюджет ресурсов: ns `lab` под ResourceQuota (requests 1CPU/1Gi,
  limits 2CPU/2Gi) и LimitRange (default limit 300m/256Mi на контейнер без
  явных значений!). Проверять `kubectl -n lab describe quota` ДО дизайна
  манифестов; surge RollingUpdate может не пролезть — используй
  `strategy: Recreate`.

## QA-контракт

- Прогон: `scripts/qa/run-module.sh modules/<имя>` = prepare.sh →
  `kubectl apply -k|-f manifests/` → verify.sh → trap-cleanup.
- Cleanup (`clean-module.sh`) удаляет манифесты с `-n lab` (ресурсы в ДРУГИХ
  namespace добивай в `verify/cleanup.sh`), затем сносит в `lab` ВООБЩЕ ВСЁ,
  включая quota/limitrange и стек модуля 18. После прогона восстанавливать:
  `scripts/bootstrap/01-apply-quotas.sh` + манифесты 18 (+ модуля, если стенд
  должен остаться живым).
- Линт: `scripts/qa/lint.sh` (yamllint, kubeconform, shellcheck, kustomize) +
  `check_links.sh` — гонять до коммита; CI дублирует это на GitHub.

## Известные грабли (уже наступали)

- В verify.sh под `set -euo pipefail` любая подстановка `$(... | grep ...)`
  обязана заканчиваться `|| true` — пустой grep иначе молча убивает скрипт
  ДО строки с fail(), и QA падает без диагностики.
- `$?` после пайпа — это код ПОСЛЕДНЕЙ команды (tail/grep), не основной.
- Grafana provisioning: uid уже запровиженного datasource сменить нельзя
  (reload 500 «data source not found», блокирует все файлы) — лечится
  `deleteDatasources:` (пример: модуль 30, loki-datasource-v2).
- Tempo 3.0: легаси-блоки `ingester:`/`compactor:` в конфиге → CrashLoop;
  поиск только TraceQL (`?q=`), параметр `?tags=` не фильтрует.
- Promtail без `HOSTNAME=spec.nodeName` и relabel в `__path__` не отгружает
  НИЧЕГО (фильтр `__host__`); verify «живости» бэкенда не доказывает доставку.
- Свежие Ubuntu-VM: остановить unattended-upgrades до Kubespray (apt-lock).

## Git/CI

- Коммиты: semantic + scope (`feat(k8s-labs):`, `fix(m18):`), тело на русском,
  атомарные, с root-cause analysis для багфиксов.
- Git-корень — `/root/lern` (репо общее для нескольких лаб); workflows GitHub
  живут ТОЛЬКО в `/root/lern/.github/workflows/` (k8s-линт:
  `k8s-labs-lint.yml` с path-фильтром `labs/kubernetes/**`).
- После push проверять `gh run list` до зелёного.
