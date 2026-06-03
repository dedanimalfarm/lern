# Review: Модули 06-10 (scheduling, config-security, observability, helm-gitops, kubeadm)

**Дата:** 2026-06-02
**Кластер:** Kubespray (3 ноды: 1 cp + 2 worker, v1.36.1, Calico CNI, kube-prometheus-stack)
**Kubeconfig:** `export KUBECONFIG=/root/.kube/kubespray.conf`

---

## Executive Summary

Модули 06-10 демонстрируют **прогрессирующее падение глубины**: от 438 строк (06) до 220 строк (09). Для сравнения: эталонный модуль 01 — 826 строк, модуль 05 — 850 строк. Модули 08-10 особенно тонкие и страдают от отсутствия кластерных пререквизитов (metrics-server, ArgoCD, kubeadm/SSH-доступ).

### Ключевые цифры

| Модуль | Строк | vs эталон (826) | Частей | Файлов | Manifest YAML |
|--------|-------|-----------------|--------|--------|---------------|
| 06-scheduling | 438 | −47% | 5 | 13 | 4 |
| 07-config-security | 372 | −55% | 5 | 16 | 8 |
| 08-observability | 284 | −66% | 4 | 10 | 2 |
| 09-helm-gitops | 220 | −73% | 3 | 13 | 0* |
| 10-kubeadm-admin | 248 | −70% | 4 | 10 | 0† |

\* Helm chart вместо статичных манифестов (charts/ + gitops/)
† Нет manifests/ — использует broken/ напрямую и работает с кластером

### Сравнение с эталоном lab01 (826 строк)

| Характеристика | 01 (эталон) | 06 | 07 | 08 | 09 | 10 |
|---------------|-------------|----|----|----|----|-----|
| Частей | 5 | 5 | 5 | 4 | 3 | 4 |
| Контр. вопросов | 5 секций | 5 | 5 | 4 | 3 | 4 |
| Итоговых вопросов | 12 | 8 | 9 | 5 | 5 | 4 |
| Task files | 2 | 4 | 3 | 3 | **0** | 3 |
| Troubleshooting инцидентов | 3 | 1(+2 текст) | 1(+2 текст) | 1 | 1 | 1 |
| Manifest-файлов | 2 | 4 | 8 | 2 | 0 | 0 |
| Шпаргалка | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

---

## 1. Cluster Readiness Assessment (модули 06-10)

### Что есть
| Компонент | Статус | Затрагивает |
|-----------|--------|-------------|
| Helm v3.20.0 | ✅ | 09 (Часть 1) |
| kube-prometheus-stack | ✅ | 08 (не используется!) |
| Calico CNI | ✅ | — |
| Control-plane taint | ✅ (штатный) | 06 (taints-пример уже есть на cp) |
| kube-state-metrics | ✅ | 08 (не упомянут) |
| `common/quotas/` | ✅ | 06 (ResourceQuota + LimitRange) |

### Что ОТСУТСТВУЕТ (блокеры)

| Компонент | Impact | Модули |
|-----------|--------|--------|
| **metrics-server** | 🔴 | 08 — `kubectl top` не работает, Часть 3 — теоретическая |
| **ArgoCD CRDs** | 🔴 | 09 — Часть 2 полностью dry-run |
| **kubeadm + SSH на cp** | 🔴 | 10 — Части 2-3 только на self-managed кластере |
| **SealedSecrets** | 🟡 | 07 — не входит в скоуп, но было бы мощным дополнением |

---

## 2. Per-Module Deep Review

### Модуль 06: Scheduling (438 строк, −47%) — ЛУЧШИЙ В ГРУППЕ

**Структура:** 5 частей: nodeSelector → taints/tolerations → affinity → quotas → troubleshooting.

**Сильные стороны:**
- Обязательная ручная разметка нод в пререквизитах — делает модуль практическим
- Три отдельных манифеста (selectors, taints, affinity) с разными подходами
- ResourceQuota и LimitRange вынесены в `common/quotas/` — переиспользуются между модулями
- verify.sh проверяет не только Ready, но и фактическое размещение (disktype=ssd)
- Хорошая cleanup-секция со снятием taints/labels

**Проблемы манифестов:**
- `manifests/taints/deploy.yaml`: busybox вместо nginx (ок — осознанный выбор для демо)

**Гапы (что добавить):**

| Приоритет | Тема | Что сделать |
|-----------|------|-------------|
| **HIGH** | `topologySpreadConstraints` | Не упомянут вообще. Критически важный scheduling-примитив (особенно с 3 зонами). Добавить манифест и упражнение |
| **MED** | `nodeAffinity` requiredDuringScheduling | Есть preferred, нет required — добавить пример с `requiredDuringSchedulingIgnoredDuringExecution` |
| **MED** | `podAntiAffinity` required vs preferred | Есть preferred anti-affinity, нет required — показать разницу |
| **MED** | `priorityClassName` | Упомянуть priority classes и preemption |
| **LOW** | `RuntimeClass` / `nodeName` | Прямое указание ноды и runtime-классы — продвинутые темы |

**Verify.sh:** проверяет 3 деплоя и размещение, но НЕ проверяет ResourceQuota/LimitRange. 🟡 MED

**Оценка:** ⭐⭐⭐⭐ — добротный модуль, лучший в этой пятёрке. Не хватает topologySpreadConstraints.

---

### Модуль 07: Config & Security (372 строки, −55%)

**Структура:** 5 частей: ConfigMap → Secret → ServiceAccount/RBAC → securityContext → troubleshooting.

**Сильные стороны:**
- RBAC проверка в verify.sh через `kubectl auth can-i` — золотой стандарт
- Хороший broken-сценарий: `runAsNonRoot: true` на root-образе → CreateContainerConfigError
- `nginxinc/nginx-unprivileged` как безопасная альтернатива nginx
- `stringData` вместо `data` в Secret — правильно для учебного контекста
- 8 манифестов (ConfigMap + Secret + RBAC + деплои) — самая богатая коллекция

**Проблемы манифестов:**
- Нет

**Гапы:**

| Приоритет | Тема | Что сделать |
|-----------|------|-------------|
| **HIGH** | Secret encryption at rest | Упомянуть, что base64 ≠ шифрование, и показать как проверить etcd encryption |
| **HIGH** | Pod Security Admission (PSA) | Модуль называется «config-security», но PSA (замена PSP) не упомянут. Добавить: `kubectl label ns lab pod-security.kubernetes.io/enforce=restricted` |
| **MED** | SealedSecrets / External Secrets Operator | Упомянуть как хранить секреты в Git безопасно |
| **MED** | `Immutable` ConfigMap/Secret | Показать `immutable: true` и объяснить зачем |
| **MED** | `capabilities: drop: ["ALL"]` | Упомянуть в securityContext-секции |
| **LOW** | `readOnlyRootFilesystem` | Уже упомянут в теории, но нет практического упражнения |

**Verify.sh:** проверяет ТОЛЬКО RBAC (SA + can-i). НЕ проверяет ConfigMap, Secret, securityContext манифесты. 🔴 HIGH — при наличии 8 манифестов проверяется только 3 (sa/role/rolebinding).

**Оценка:** ⭐⭐⭐½ — хорошая RBAC-часть, но конфиг-безопасность недостаточно раскрыта, verify.sh узкий.

---

### Модуль 08: Observability (284 строки, −66%) — КРИТИЧЕСКИ ТОНКИЙ

**Структура:** 4 части: events/conditions → logs → metrics → troubleshooting (CrashLoopBackOff runbook).

**Сильные стороны:**
- Линейный runbook деградации — практическая ценность
- Структурированные логи (`level=info`) — правильный подход
- `logs --previous` объяснён с нюансом (короткоживущий контейнер может не сохранить логи)
- Хороший broken-сценарий: exit 1 → CrashLoopBackOff

**Проблемы:**
- `solutions/01-crashloop/deploy.yaml`: нет `resources` и `securityContext` (стилистический разнос с `obs-demo`)
- metrics-server НЕ установлен → `kubectl top` не работает, Часть 3 чисто теоретическая

**Гапы:**

| Приоритет | Тема | Что сделать |
|-----------|------|-------------|
| **🔴 HIGH** | metrics-server установка | Добавить инструкцию: `kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml` |
| **🔴 HIGH** | Использовать существующий Prometheus/Grafana | На кластере уже есть kube-prometheus-stack! Добавить Часть 4: Grafana dashboards, Prometheus queries, Alertmanager |
| **HIGH** | `kubectl get events --field-selector` | Фильтрация events по типу/объекту — мощный диагностический приём |
| **MED** | audit logs | Упомянуть `kube-apiserver` audit policy |
| **MED** | `kubectl debug` (ephemeral containers) | Как заглянуть в контейнер без shell |
| **MED** | kubelet logs | `journalctl -u kubelet` для проблем на уровне ноды |
| **LOW** | `crictl` / `nerdctl` | Когда kubectl недостаточно — container runtime debug |

**Verify.sh:** проверяет логи и deployment, но НЕ проверяет доступность metrics-server. 🟡 MED

**Оценка:** ⭐⭐½ — самый тонкий содержательный модуль. При наличии Prometheus/Grafana на кластере их полное игнорирование — упущенная возможность. Runbook хорош, но observability ≠ только logs + events.

---

### Модуль 09: Helm & GitOps (220 строк, −73%) — САМЫЙ ТОНКИЙ

**Структура:** 3 части: Helm chart → ArgoCD → troubleshooting. **Нет отдельных task-файлов.**

**Сильные стороны:**
- Полный Helm chart (`charts/demo-app/`) с values, templates, probes, securityContext
- верный `networking.k8s.io/v1` Ingress, `apps/v1` Deployment
- ArgoCD Application с `automated`/`prune`/`selfHeal` sync policy
- `helm lint` + `helm template` до установки — правильный workflow

**Проблемы:**
1. 🔴 **ArgoCD не установлен** → Часть 2 полностью dry-run, troubleshooting-сценарий невоспроизводим
2. 🟡 **Solution теряет syncPolicy**: `solutions/01-argocd-path/app.yaml` не содержит `syncPolicy` — при применении студент потеряет automated sync
3. 🟡 **AppProject слишком открыт**: `clusterResourceWhitelist: ['*'/'*']` + `sourceRepos: ['*']` — ок для лабы, но противоречит идее GitOps-границ
4. 🟢 **verify.sh**: `kubectl apply --dry-run=client -f project.yaml` без `-n argocd` — создаст в default ns если CRD установлены

**Гапы:**

| Приоритет | Тема | Что сделать |
|-----------|------|-------------|
| **🔴 HIGH** | ArgoCD установка | Добавить инструкцию: `kubectl create ns argocd && kubectl apply -n argocd -f https://...stable/manifests/install.yaml`. Без этого 50% модуля — теория. |
| **🔴 HIGH** | Восстановить task files | Создать `tasks/` с отдельными заданиями как в других модулях |
| **HIGH** | `helm rollback` + `helm history` | Базовые операции отсутствуют |
| **HIGH** | `helm dependency` / umbrella charts | Упомянуть как паттерн |
| **MED** | `helm test` / chart hooks | Показать `helm test` для верификации релиза |
| **MED** | Multiple value files | `-f values-prod.yaml` — переопределение для окружений |
| **MED** | `helm repo add` + `helm search` | Установка из репозиториев, не только из локального chart |
| **LOW** | Helm secrets plugin | `helm secrets` для зашифрованных values |
| **LOW** | App of Apps pattern | Упомянуть для мультикластерного GitOps |

**Verify.sh:** `helm lint` + `helm template` работают (Helm установлен). ArgoCD dry-run — мягкий WARN без CRDs.

**Оценка:** ⭐⭐½ — база Helm есть, но GitOps-часть чисто теоретическая (нет ArgoCD). 220 строк на ОБЕ темы — экстремально мало.

---

### Модуль 10: Kubeadm Admin (248 строк, −70%)

**Структура:** 4 части: drain/cordon → static pods → certs → troubleshooting (PDB). Плюс `setup-guide.md`.

**Сильные стороны:**
- Часть 1 (drain/cordon/PDB) работает на ЛЮБОМ кластере — отличная практическая ценность
- setup-guide.md: полная инструкция развёртывания kubeadm с нуля на Debian 12
- Хороший broken-сценарий: PDB `minAvailable:1` + `replicas:1` блокирует drain
- Правильное разделение: что работает на managed, а что — только на self-managed

**Проблемы:**
1. 🟡 **setup-guide.md**: `sudo chown $(id -u):$(id -g) /etc/kubernetes/admin.conf` меняет владельца системного файла. Правильно: chown копию в `$HOME/.kube/config`
2. 🟢 **setup-guide.md**: Calico URL `docs.projectcalico.org` устарел → `raw.githubusercontent.com/.../calico/master/manifests/calico.yaml`
3. 🔴 **Части 2-3 недоступны**: static pods и certs требуют SSH на control-plane (на managed-кластерах недоступны)

**Гапы:**

| Приоритет | Тема | Что сделать |
|-----------|------|-------------|
| **🔴 HIGH** | etcd backup/restore | Критическая admin-операция не покрыта: `etcdctl snapshot save`, восстановление |
| **HIGH** | `kubeadm upgrade` | Обновление кластера — базовая admin-задача |
| **HIGH** | kubelet-конфигурация | `/var/lib/kubelet/config.yaml`, резервация ресурсов (`systemReserved`, `kubeReserved`) |
| **MED** | `kubectl certificate approve` | Ручное одобрение CSR |
| **MED** | kubeconfig-генерация | `kubectl config set-credentials`, создание ограниченных kubeconfig-файлов |
| **MED** | control-plane join | Добавление второго control-plane для HA |
| **LOW** | `kubeadm reset` + переустановка | Полный цикл пересоздания ноды |

**Verify.sh:** ТОЛЬКО baseline: список нод, kube-system pods, coredns. 🔴 HIGH — не проверяет drain/PDB/static pods. Это не verify, а smoke test.

**Оценка:** ⭐⭐⭐ — хорошая admin-база, но 70% короче эталона. setup-guide.md добавляет практической ценности, но сам модуль требует kubeadm-кластера для полного выполнения.

---

## 3. Cross-Module Issues

### 3.1 Тренд падения глубины

```
826 ── module 01 (gold standard)
850 ── module 05 (deepest)
─── разрыв ───
438 ── module 06
372 ── module 07
284 ── module 08
220 ── module 09
248 ── module 10
```

Модули 08-10 суммарно (752 строки) меньше одного модуля 01 (826 строк).

### 3.2 Блокеры кластера (сводная)

| Модуль | Блокер | Эффект |
|--------|--------|--------|
| 08 | Нет metrics-server | `kubectl top` — только пример вывода в теории |
| 09 | Нет ArgoCD CRDs | Application/AppProject — dry-run, troubleshooting невоспроизводим |
| 10 | Нет kubeadm/SSH | Части 2-3 — чисто теоретические |

### 3.3 Verify.sh Gaps

| Модуль | Пропущено | Критичность |
|--------|-----------|-------------|
| 06 | ResourceQuota, LimitRange | 🟡 MED |
| 07 | ConfigMap, Secret, securityContext manifests | 🔴 HIGH |
| 08 | metrics-server availability | 🟡 MED |
| 09 | — (warn-only для ArgoCD — ок) | 🟢 OK |
| 10 | drain, PDB, static pods, certs | 🔴 HIGH |

### 3.4 Отсутствующие темы (общие)

- **kubectl explain** — только в модуле 01, в 06-10 не упоминается
- **kubectl diff** — `kubectl diff -f` для предпросмотра изменений
- **kubectl wait** — `--for=condition=` для скриптов
- **kubectl patch** — merge vs JSON patch
- **ExternalDNS / cert-manager** — companion-проекты для Ingress (упомянуть)

---

## 4. Prioritized Action Items

### 🔴 Critical (модуль неработоспособен без этого)

1. **Установить metrics-server** (модуль 08)
   ```
   kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
   ```

2. **Установить ArgoCD** (модуль 09)
   ```
   kubectl create ns argocd
   kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
   ```

3. **Модуль 07: расширить verify.sh** — добавить проверки ConfigMap, Secret, securityContext

4. **Модуль 10: расширить verify.sh** — добавить проверку PDB и drain-поведения

### 🟡 High (значительно улучшает качество)

5. **Модуль 06: добавить topologySpreadConstraints** — упражнение + манифест

6. **Модуль 07: добавить Pod Security Admission** — практический пример с restricted-политикой

7. **Модуль 08: добавить Prometheus/Grafana-часть** — использовать существующий стек на кластере

8. **Модуль 09: починить solution-файл** — вернуть `syncPolicy` в `solutions/01-argocd-path/app.yaml`

9. **Модуль 09: создать task files** — вынести практические задания в отдельные md-файлы

10. **Модуль 09: добавить helm rollback и helm history** — базовые операции с релизом

11. **Модуль 10: добавить etcd backup/restore** — критическая admin-операция

12. **Модуль 10: исправить setup-guide.md** — `chown` копии, не системного файла; обновить Calico URL

### 🟢 Medium (улучшает покрытие)

13. **Модуль 06: добавить nodeAffinity required** — сейчас только preferred

14. **Модуль 07: добавить SealedSecrets упоминание** — как хранить секреты в Git

15. **Модуль 08: добавить `kubectl debug`** — ephemeral containers для дебага

16. **Модуль 09: добавить `helm dependency` / umbrella charts** — продвинутый Helm

17. **Модуль 10: добавить `kubeadm upgrade`** — обновление кластера

18. **Модуль 08: синхронизировать solution с demo** — добавить resources/securityContext

### 🟢 Low (косметика)

19. **Модуль 09: AppProject hardening** — ограничить `sourceRepos` и `clusterResourceWhitelist`

20. **Модуль 09: исправить dry-run namespace** — добавить `-n argocd` в verify.sh

21. **Модуль 10: добавить control-plane join** — multi-master setup

---

## 5. Quick-Win: Cluster Setup для 08-09

Дополнить `/root/lern/labs/kubernetes/scripts/setup-cluster.sh`:

```bash
# === Module 08: metrics-server ===
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# === Module 09: ArgoCD ===
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s

# ArgoCD CLI (опционально)
# curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
# chmod +x /usr/local/bin/argocd
```

---

## 6. Итоговая таблица

| Модуль | Строк | Частей | Итог. вопросов | Блокеры кластера | Verify gaps | Оценка |
|--------|-------|--------|---------------|-----------------|-------------|--------|
| 06-scheduling | 438 | 5 | 8 | — | 🟡 Quota | ⭐⭐⭐⭐ |
| 07-config-security | 372 | 5 | 9 | — | 🔴 CM/Secret/SC | ⭐⭐⭐½ |
| 08-observability | 284 | 4 | 5 | 🔴 metrics-server | 🟡 metrics | ⭐⭐½ |
| 09-helm-gitops | 220 | 3 | 5 | 🔴 ArgoCD | 🟢 OK | ⭐⭐½ |
| 10-kubeadm-admin | 248 | 4 | 4 | 🔴 kubeadm/SSH | 🔴 drain/PDB | ⭐⭐⭐ |

**Главный вывод:** модули 01-05 (базовые) имеют глубину 500-850 строк и полностью работоспособны на кластере (кроме StorageClass). Модули 06-10 резко теряют в объёме (220-438 строк) и три из пяти имеют критические блокеры кластера. Приоритет: сначала установить metrics-server и ArgoCD, затем углубить модули 08 и 09.
