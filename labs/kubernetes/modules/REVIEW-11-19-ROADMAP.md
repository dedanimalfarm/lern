# Review: Модули 11-19 + ROADMAP

**Дата:** 2026-06-03
**Кластер:** Kubespray (3 ноды: 1 cp + 2 worker, v1.36.1, Calico CNI, kube-prometheus-stack)
**Kubeconfig:** `export KUBECONFIG=/root/.kube/kubespray.conf`

---

## Часть 1: Обзор модулей 11-19

### Executive Summary

Модули 11-19 — продвинутые темы. Все тонкие (247-312 строк, ≈⅓ эталонного модуля 01), но качественно сделанные: единообразная структура, 4-5 частей, 12-15 контрольных вопросов, 5-6 итоговых вопросов, шпаргалка.

**Главное открытие:** кластер УЖЕ частично настроен под эти модули — WebApp CRD installed, PSA restricted на `lab-restricted`, kube-prometheus-stack в `monitoring`. Большинство модулей готовы к прогону «из коробки».

### Сводная таблица

| Модуль | Строк | Частей | Файлов | Контр. вопросов | Итог. вопросов | Инцидентов | Оценка |
|--------|-------|--------|--------|----------------|---------------|------------|--------|
| 11-autoscaling | 304 | 4 | 12 | 12 | 5 | 3 | ⭐⭐⭐½ |
| 13-resilience | 248 | 4 | 11 | 12 | 5 | 2 | ⭐⭐⭐ |
| 14-pod-security-admission | 250 | 4 | 12 | 12 | 5 | 3 | ⭐⭐⭐⭐ |
| 15-network-policy-enforced | 312 | 5 | 13 | 15 | 6 | 3 | ⭐⭐⭐⭐ |
| 17-metrics-alerting | 299 | 5 | 10 | 15 | 5 | 3 | ⭐⭐⭐⭐ |
| 19-crd-operators | 247 | 5 | 10 | 15 | 5 | 2 | ⭐⭐⭐⭐ |

### Сравнение с эталоном lab01 (826 строк)

```
826 ──█ 01 (gold standard)
████████████████████████████████████████

312 ──█ 15 (best of 11-19)
304 ──█ 11
299 ──█ 17
250 ──█ 14
248 ──█ 13
247 ──█ 19
```

Все модули 11-19 — **ровно ⅓ глубины эталона**.

---

## 2. Per-Module Review

### Модуль 11: Autoscaling (304 строки)

**Структура:** 4 части: HPA CPU → нагрузка/масштабирование → VPA/Cluster Autoscaler (обзор) → troubleshooting.

**Сильные стороны:**
- Правильный `autoscaling/v2` HPA с `stabilizationWindowSeconds: 120` на scale-down
- Использует канонический образ `registry.k8s.io/hpa-example`
- Три troubleshooting-инцидента: `<unknown>` метрика, нет metrics-server, Pending при scale-up
- Task 03 (Cluster Autoscaler) — обзорный, честно говорит где работает

**Проблемы:**
- 🔴 **metrics-server не установлен** → HPA показывает `<unknown>`, scale-up не происходит

**Гапы:**

| Приоритет | Тема |
|-----------|------|
| **MED** | `behavior.scaleDown.stabilizationWindowSeconds` — объяснить почему scale-down медленнее |
| **MED** | HPA на памяти (memory-based) в дополнение к CPU |
| **MED** | `containerResource` metrics (HPA v2 на кастомные метрики изнутри пода) |
| **LOW** | VPA — добавить манифест VPA (хотя бы CRD-обзор) |

**Оценка:** ⭐⭐⭐½ — база HPA хорошая, но без metrics-server модуль чисто теоретический.

---

### Модуль 13: Resilience (248 строк)

**Структура:** 4 части: topologySpreadConstraints → podAntiAffinity → PDB → troubleshooting.

**Сильные стороны:**
- `topologySpreadConstraints` с `nodeTaintsPolicy: Honor` — современный подход
- Три реплики с принудительным спредом по нодам (на 3-нодовом кластере)
- `requiredDuringScheduling` broken-сценарий — под не садится при нехватке нод
- verify.sh проверяет фактическое распределение по нодам

**Проблемы:**
- `manifests/app.yaml` (линия 1-3): не указан `apiVersion` — **это ok**, в файле есть `apiVersion: apps/v1`

**Гапы:**

| Приоритет | Тема |
|-----------|------|
| **MED** | Комбинация spread + PDB для zero-downtime maintenance — показать drain ноды с обоими |
| **MED** | `podAntiAffinity.requiredDuringScheduling` с `topologyKey: zone` |
| **LOW** | `matchLabelKeys` (k8s 1.29+) — более точный anti-affinity по версии деплоя |

**Оценка:** ⭐⭐⭐ — хорошо, но тоньше чем хотелось бы для такой важной темы.

---

### Модуль 14: Pod Security Admission (250 строк)

**Структура:** 4 части: PSA (Pod Security Standards) → ValidatingAdmissionPolicy (CEL) → Policy Engines (Kyverno/OPA обзор) → troubleshooting.

**Сильные стороны:**
- PSA на `lab-restricted` namespace — **УЖЕ настроен на кластере!**
- VAP манифест `no-latest-tag` — реальный CEL-based запрет `:latest` тегов
- Обзор Kyverno vs Gatekeeper в Части 3 — честный, без требования установки
- `good-pod.yaml` использует `nginxinc/nginx-unprivileged` + `seccompProfile: RuntimeDefault` + `capabilities.drop: [ALL]`

**Проблемы:**
1. 🟡 **verify.sh jsonpath bug** (MED): `pod-security\.kubernetes\.io/enforce` — бэкслеш-эскейпинг точек не портабелен. Правильно: `{.metadata.labels['pod-security.kubernetes.io/enforce']}`
2. 🟢 **CEL expression** (LOW): `endsWith(':latest')` — матчит `:v1.0-latest` (false positive). Правильно: `c.image.split(':').last() != 'latest'`
3. 🟢 **good-pod.yaml** (LOW): `runAsNonRoot: true` дублируется на pod-level и container-level

**Гапы:**

| Приоритет | Тема |
|-----------|------|
| **HIGH** | `matchConditions` в VAP — фильтрация по namespace label (не применять VAP к kube-system) |
| **MED** | `warn`/`audit` режимы — показать разницу на практике |
| **LOW** | `paramKind` VAP — параметризованные политики |

**Оценка:** ⭐⭐⭐⭐ — лучший в группе по содержанию, но нужно починить verify.sh.

---

### Модуль 15: Network Policy Enforced (312 строк) — BEST IN BATCH

**Структура:** 5 частей: модель/enforcement → микросегментация web→api→db → egress/DNS → namespaceSelector/ipBlock → troubleshooting.

**Сильные стороны:**
- **Реальная микросегментация:** 3-tier приложение (web/api/db) с 5 политиками
- Политики НУМЕРОВАНЫ (00-default-deny, 01-allow-dns, 02-web, 03-api, 04-db) — порядок применения очевиден
- `allow-dns` корректно покрывает И nodelocaldns (169.254.25.10), И CoreDNS (k8s-app=kube-dns)
- Enforcement ПРОВЕРЯЕТСЯ: Calico на кластере обеспечивает реальную фильтрацию
- `namespaceSelector` и `ipBlock` в части 4
- verify.sh проверяет ВСЕ 5 политик + CNI enforcement

**Проблемы:**
- 🟢 Нет broken YAML-файла (LOW) — сценарий описывает применение default-deny без allow-dns; студент делает это вручную

**Оценка:** ⭐⭐⭐⭐ — самая полная микросегментация в лабах. Модуль 04 даёт базу NetworkPolicy, этот — энфорсмент.

---

### Модуль 17: Metrics & Alerting (299 строк)

**Структура:** 5 частей: установка kube-prometheus-stack → PromQL → ServiceMonitor → Grafana/алерты → troubleshooting.

**Сильные стороны:**
- **Стек УЖЕ установлен** в `monitoring` namespace — студенту не нужно ставить (Часть 1 — опционально)
- ServiceMonitor манифест с label `release: kps` (правильный для нашего стека)
- PrometheusRule с recording rule + alert `MetricsAppDown`
- Использует `quay.io/brancz/prometheus-example-app` — канонический пример с `/metrics`
- verify.sh проверяет наличие стека (graceful warn, не fail)

**Проблемы:**
- 🟢 Нет broken YAML-файла (LOW) — сценарий описывает ServiceMonitor без label `release: kps`
- Нет манифестов для Grafana dashboard (только ServiceMonitor + PrometheusRule)

**Гапы:**

| Приоритет | Тема |
|-----------|------|
| **HIGH** | Grafana dashboard — показать JSON-модель дашборда или ConfigMap-based dashboard |
| **MED** | Alertmanager routing — `alertmanager.yaml` с роутингом по severity |
| **MED** | `additionalAlertRelabelConfigs` / `metricRelabelings` — фильтрация метрик |
| **LOW** | Thanos / PrometheusAgent для долгосрочного хранения |

**Оценка:** ⭐⭐⭐⭐ — хорошее введение в Prometheus-стек, использует реальный кластерный стек.

---

### Модуль 19: CRD & Operators (247 строк)

**Структура:** 5 частей: CRD определение → Custom Resources/схема → Operator pattern → kubectl с CR → troubleshooting.

**Сильные стороны:**
- **WebApp CRD УЖЕ зарегистрирован** на кластере + инстанс `my-webapp` работает
- CRD включает: схему (`image` required, `replicas` 1-10), `additionalPrinterColumns`, `shortNames: wa`, `categories: [all]`, `subresources.status`
- Понимание что CRD без контроллера ≠ оператор (секция 3.1)
- Ссылается на prometheus-operator из модуля 17 как реальный пример оператора
- Broken: `replicas: 99` (нарушает max:10) + отсутствует `image`

**Проблемы:**
- Нет контроллера (оператор только обсуждается теоретически)

**Гапы:**

| Приоритет | Тема |
|-----------|------|
| **HIGH** | Простейший контроллер — bash-скрипт или `kubectl` в цикле `while true`, который читает WebApp CR и создаёт Deployment |
| **MED** | `conversion.webhook` — упомянуть multiple API versions |
| **MED** | `schema.openAPIV3Schema` с `x-kubernetes-validations` (CEL-правила как в VAP) |
| **LOW** | `kubebuilder` / `operator-sdk` — scaffolding для реальных операторов |

**Оценка:** ⭐⭐⭐⭐ — отличное введение в CRD, но оператор-паттерн чисто теоретический.

---

## 3. Сводка багов и проблем

### Баги манифестов (3 medium, 3 low)

| # | Модуль | Файл | Проблема | Severity |
|---|--------|------|----------|----------|
| 1 | 14 | `verify/verify.sh:11` | `jsonpath` с `\.` — не портабелен, нужно `['pod-security.kubernetes.io/enforce']` | 🟡 MED |
| 2 | 14 | `vap-no-latest.yaml:16` | `endsWith(':latest')` — false positive на `:v1.0-latest` | 🟢 LOW |
| 3 | 14 | `good-pod.yaml:12,22` | `runAsNonRoot: true` дублируется | 🟢 LOW |
| 4 | 15 | `broken/scenario-01/` | Нет broken YAML — только README с командами | 🟢 LOW |
| 5 | 17 | `broken/scenario-01/` | Нет broken YAML — только README с командами | 🟢 LOW |

### Кластерные блокеры

| Блокер | Модуль | Статус |
|--------|--------|--------|
| metrics-server | 11 | 🔴 Не установлен — HPA не масштабирует |
| kube-prometheus-stack | 17 | ✅ Уже установлен |
| WebApp CRD | 19 | ✅ Уже зарегистрирован |
| PSA restricted | 14 | ✅ `lab-restricted` уже настроен |
| Calico CNI | 15 | ✅ Enforcement работает |
| ArgoCD | 09 | 🔴 Не установлен (из обзора 06-10) |
| StorageClass | 05/03 | 🔴 Не установлен (из обзора 01-05) |

### Verify.sh gaps

| Модуль | Пропущено |
|--------|-----------|
| 11 | Не проверяет metrics-server доступность (graceful warn) |
| 13 | ok |
| 14 | 🟡 jsonpath bug — может ложно fail |
| 15 | ok (лучший verify.sh) |
| 17 | ok (graceful warn) |
| 19 | ok |

---

## Часть 2: ROADMAP

### 2.1 Общая оценка лаб

| Метрика | Значение |
|---------|----------|
| Всего модулей | 16 (01-11, 13-15, 17, 19) |
| Пропущено | 12, 16, 18 |
| Суммарно строк README | ≈9,000 |
| Средняя глубина модуля | ≈560 строк |
| Эталонная глубина (lab01) | 826 строк |
| Самый глубокий | 05-storage (850 строк) |
| Самый тонкий | 09-helm-gitops (220 строк) |

### 2.2 Пропущенные модули — что добавить

**Модуль 12 — Service Mesh (Istio / Gateway API)**
- Gateway API vs Ingress
- Traffic splitting (canary)
- mTLS между сервисами
- `VirtualService` + `DestinationRule`
- Observability через Kiali/Jaeger

**Модуль 16 — Backup & Disaster Recovery (Velero)**
- Velero install + backup кластера
- Восстановление в другой namespace
- Scheduled backups
- Restore-only DR-сценарий

**Модуль 18 — Advanced GitOps (Flux / Image Updater / App of Apps)**
- Flux как альтернатива ArgoCD
- Image automation (Flux Image Update)
- App of Apps паттерн
- Multi-cluster GitOps

### 2.3 Приоритеты ближайших действий

#### 🔴 Critical (кластер не готов — блокирует модули)

| # | Действие | Модули |
|---|----------|--------|
| C1 | Установить **metrics-server** | 08, 11 |
| C2 | Установить **StorageClass** (local-path-provisioner) | 03, 05 |
| C3 | Установить **ArgoCD** | 09 |

Единый setup-скрипт для C1-C3:
```bash
# metrics-server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# StorageClass (rancher local-path-provisioner)
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.29/deploy/local-path-storage.yaml
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# ArgoCD
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

#### 🟡 High (качество и глубина)

| # | Действие | Модуль |
|---|----------|--------|
| H1 | Починить `verify.sh` jsonpath в модуле 14 | 14 |
| H2 | Добавить Grafana dashboard манифест | 17 |
| H3 | Добавить контроллер (bash while-скрипт) для WebApp CRD | 19 |
| H4 | Добавить `topologySpreadConstraints` в модуль 06 | 06 |
| H5 | Добавить PSA секцию в модуль 07 | 07 |
| H6 | Интегрировать Prometheus/Grafana в модуль 08 | 08 |
| H7 | Восстановить task files в модуле 09 | 09 |
| H8 | Исправить `setup-guide.md` (chown, Calico URL) | 10 |

#### 🟢 Medium (расширение покрытия)

| # | Действие | Модуль |
|---|----------|--------|
| M1 | HPA на memory + container metrics | 11 |
| M2 | Комбинация spread + PDB для drain | 13 |
| M3 | `matchConditions` в VAP | 14 |
| M4 | Alertmanager routing config | 17 |
| M5 | `x-kubernetes-validations` (CEL) в CRD | 19 |
| M6 | `helm rollback` + `helm history` | 09 |
| M7 | etcd backup/restore | 10 |
| M8 | `externalTrafficPolicy: Local` | 04 |

### 2.4 Идеи Capstone-проектов

#### Capstone A: «Zero-Trust Платформа» (8-12 часов)

**Сценарий:** развернуть трёхуровневое приложение (web→api→db) с полным Zero-Trust стеком.

| Шаг | Модуль | Что делаем |
|-----|--------|------------|
| 1 | 05 | StorageClass + PVC для db |
| 2 | 07 | ConfigMap/Secret для конфигурации + RBAC (SA на каждый tier) |
| 3 | 09 | Упаковать приложение в Helm chart |
| 4 | 14 | PSA restricted на неймспейс |
| 5 | 15 | NetworkPolicy микросегментация web→api→db |
| 6 | 13 | topologySpread + PDB для отказоустойчивости |
| 7 | 11 | HPA на web и api |
| 8 | 17 | ServiceMonitor + PrometheusRule алерты |
| 9 | 19 | WebApp CRD для декларативного описания приложения |
| 10 | 09 | ArgoCD Application для GitOps-деплоя |

**Критерии приёмки:**
- Все поды с `securityContext` (non-root, readOnlyRootFS, drop ALL)
- PSA restricted enforced — никаких privileged
- NetworkPolicy: default-deny + точечные разрешения (web→api, api→db, все→DNS, monitoring→metrics)
- HPA масштабирует web при нагрузке
- Grafana dashboard показывает метрики приложения
- Alertmanager отправляет алерт при `up == 0`

#### Capstone B: «Platform Engineering Sandbox» (12-16 часов)

**Сценарий:** построить внутреннюю платформу для разработчиков — self-service через CRD + GitOps.

| Компонент | Технология |
|-----------|-----------|
| API платформы | CRD `WebApp` + контроллер (bash/kubectl) |
| GitOps engine | ArgoCD (App of Apps) |
| Observability | Prometheus + Grafana + Loki (по желанию) |
| Policy engine | VAP (no `:latest`, required labels) + PSA restricted |
| Ingress | ingress-nginx + cert-manager (по желанию) |
| Secrets | SealedSecrets (по желанию) |

**Контроллер (bash):**
```bash
while true; do
  for cr in $(kubectl get webapp -A -o name); do
    name=$(basename $cr)
    ns=$(dirname $cr | cut -d/ -f1)
    image=$(kubectl get webapp $name -n $ns -o jsonpath='{.spec.image}')
    replicas=$(kubectl get webapp $name -n $ns -o jsonpath='{.spec.replicas}')
    # Создать/обновить Deployment
    kubectl -n $ns create deploy $name --image=$image --replicas=$replicas --dry-run=client -o yaml | kubectl apply -f -
    # Обновить status.availableReplicas
    ready=$(kubectl -n $ns get deploy $name -o jsonpath='{.status.readyReplicas}')
    kubectl -n $ns patch webapp $name --subresource status --type merge -p "{\"status\":{\"availableReplicas\":$ready}}"
  done
  sleep 30
done
```

#### Capstone C: «Production Readiness Audit» (6-8 часов)

**Сценарий:** аудит существующего приложения на production-readiness.

| Аспект | Проверка |
|--------|----------|
| **Scheduling** | Pod spread по нодам? Anti-affinity для HA? |
| **Resources** | Requests/limits у всех контейнеров? QoS класс? |
| **Probes** | Readiness + liveness настроены и НЕ мешают друг другу? |
| **Security** | PSA restricted? runAsNonRoot? No privileged? readOnlyRootFS? |
| **Network** | NetworkPolicy микросегментация? DNS разрешён? Egress ограничен? |
| **Resilience** | PDB есть? topologySpread работает? |
| **Scaling** | HPA настроен? min/max реплик адекватны? |
| **Observability** | ServiceMonitor есть? PrometheusRule алерты? Grafana dashboard? |
| **Config** | ConfigMap/Secret вынесены из образа? Не зашиты ли секреты в values.yaml? |

**Результат:** RAG-отчёт (Red/Amber/Green) + список рекомендаций.

#### Capstone D: «Full CI/CD Pipeline» (8-10 часов)

**Сценарий:** сквозной пайплайн от кода до production.

```
GitHub push
  → Docker build & push
  → Helm chart update (new image tag)
  → ArgoCD sync (automated)
  → Prometheus alert if deploy fails
  → HPA scale on load
  → Grafana dashboard показывает deploy-метрики
```

**Ключевые точки:**
- ArgoCD `selfHeal` откатывает ручные правки
- `canary` deployment через Argo Rollouts (продвинутый вариант)
- PrometheusRule `Absent` — алерт если метрики пропали

### 2.5 Трёхмесячный план

#### Месяц 1: Закрыть блокеры + базовое качество

| Неделя | Задачи |
|--------|--------|
| W1 | C1-C3: metrics-server + StorageClass + ArgoCD |
| W1 | H1-H3: fix verify.sh (14), Grafana dashboard (17), bash-контроллер (19) |
| W2 | H4-H5: topologySpread в 06, PSA в 07 |
| W2 | H6: Prometheus/Grafana-часть в 08 |
| W3 | H7-H8: task files в 09, fix setup-guide.md (10) |
| W4 | Прогнать ВСЕ модули 01-19 на кластере, записать баги |

#### Месяц 2: Расширение покрытия

| Неделя | Задачи |
|--------|--------|
| W5 | M1-M3: HPA memory, spread+PDB, VAP matchConditions |
| W6 | M4-M5: Alertmanager routing, CRD CEL validations |
| W7 | M6-M8: helm rollback, etcd backup, externalTrafficPolicy |
| W8 | Написать модули 12 (Service Mesh) + 16 (Velero backup) |

#### Месяц 3: Capstone + финализация

| Неделя | Задачи |
|--------|--------|
| W9 | Capstone A/B на выбор — пройти end-to-end |
| W10 | Capstone C — аудит и документирование |
| W11 | Capstone D — CI/CD пайплайн |
| W12 | Финальный review всех модулей, обновление скриншотов/вывода команд |

---

## 4. Сводный индекс всех модулей

| # | Модуль | Строк | Оценка | Блокеры кластера | Verify gaps | Основной гап |
|---|--------|-------|--------|-----------------|-------------|-------------|
| 01 | kubectl-basics | 826 | ⭐⭐⭐⭐⭐ | — | — | Эталон |
| 02 | pods-lifecycle | 645 | ⭐⭐⭐⭐ | — | — | startupProbe фрагмент |
| 03 | workloads | 587 | ⭐⭐⭐½ | SC (STS) | 🔴 STS | StatefulSet неглубоко |
| 04 | networking | 497 | ⭐⭐⭐ | Ingress ctrl | 🔴 NP+NPOL | DNS-секция тонкая |
| 05 | storage | 850 | ⭐⭐⭐⭐⭐ | SC (всё) | 🟡 PV | 4 части вместо 5 |
| 06 | scheduling | 438 | ⭐⭐⭐⭐ | — | 🟡 Quota | topologySpread |
| 07 | config-security | 372 | ⭐⭐⭐½ | — | 🔴 CM/Secret/SC | Нет PSA |
| 08 | observability | 284 | ⭐⭐½ | metrics-server | 🟡 metrics | Нет Prom/Grafana |
| 09 | helm-gitops | 220 | ⭐⭐½ | ArgoCD | 🟢 OK | Нет task files |
| 10 | kubeadm-admin | 248 | ⭐⭐⭐ | kubeadm/SSH | 🔴 drain/PDB | Нет etcd backup |
| 11 | autoscaling | 304 | ⭐⭐⭐½ | metrics-server | 🟢 OK | Memory HPA |
| 12 | — | — | — | — | — | **НЕ СУЩЕСТВУЕТ** |
| 13 | resilience | 248 | ⭐⭐⭐ | — | 🟢 OK | spread+PDB |
| 14 | PSA | 250 | ⭐⭐⭐⭐ | — | 🟡 jsonpath | matchConditions |
| 15 | netpol-enforced | 312 | ⭐⭐⭐⭐ | — | 🟢 OK | Нет broken YAML |
| 16 | — | — | — | — | — | **НЕ СУЩЕСТВУЕТ** |
| 17 | metrics-alerting | 299 | ⭐⭐⭐⭐ | — | 🟢 OK | Grafana dashboard |
| 18 | — | — | — | — | — | **НЕ СУЩЕСТВУЕТ** |
| 19 | crd-operators | 247 | ⭐⭐⭐⭐ | — | 🟢 OK | Нет контроллера |
