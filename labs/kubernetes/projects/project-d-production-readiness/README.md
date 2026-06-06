# Project D: Production Readiness Audit (аудит прод-готовности)

## Оглавление
<!-- TOC -->
- [Чек-лист прод-готовности (11 критериев)](#----11-)
- [Предварительные требования](#-)
- [Стартовая проверка](#-)
- [Часть 1: Аудит «наивного» приложения (ДО)](#-1----)
- [Часть 2: Харденинг до прод-готовности (ПОСЛЕ)](#-2-----)
- [Аудит-инструмент (`audit/audit.sh`)](#--auditauditsh)
- [Проверка](#)
- [Финальная карта ресурсов](#--)
- [Теоретические вопросы (итоговые)](#--)
- [Практические задания (отработка)](#--)
- [Чему вы научились](#--)
- [Уборка](#)
<!-- /TOC -->


> ⏱ время ~30 мин · сложность 4/5 · пререквизиты: Трек 1 и Трек 3

Цель: научиться отличать «работает на демо» от «готово к проду» и довести
приложение до прод-готовности по чек-листу из 11 критериев. Это СИНТЕЗ всей лабы:
надёжность, здоровье, ресурсы, безопасность, сеть, масштабирование, наблюдаемость.
В центре — переиспользуемый `audit/audit.sh`, который ставит [PASS]/[FAIL] по
каждому критерию для ЛЮБОГО Deployment.

> Опирается на установленные аддоны: metrics-server (HPA), kube-prometheus-stack
> (ServiceMonitor), Calico (NetworkPolicy). Все есть на нашем Kubespray.

---

## Чек-лист прод-готовности (11 критериев)

| # | Критерий | Зачем | Модуль |
|---|----------|-------|--------|
| 1 | `replicas >= 2` | переживает падение пода/ноды | 03, 13 |
| 2 | PodDisruptionBudget | drain не уведёт все реплики разом | 10, 13 |
| 3 | topologySpread / podAntiAffinity | реплики на РАЗНЫХ нодах | 06, 13 |
| 4 | readiness + liveness probes | не слать трафик в неготовый; рестарт зависшего | 02 |
| 5 | requests + limits | предсказуемость, QoS, не BestEffort | 02, 06, 12 |
| 6 | securityContext (nonRoot, noPrivEsc, ROfs, drop ALL, seccomp) | минимум прав контейнера; проходит PSA restricted | 07, 14 |
| 7 | образ запиннен (не `:latest`) | воспроизводимость деплоя | 03, 14 |
| 8 | HorizontalPodAutoscaler | держит нагрузку | 11 |
| 9 | default-deny NetworkPolicy | Zero-Trust сеть | 04, 15 |
| 10 | секреты через `secretKeyRef` (не plaintext env) | не светить пароли | 07, 16 |
| 11 | ServiceMonitor (метрики) | наблюдаемость | 17 |

---

## Предварительные требования

```bash
export KUBECONFIG=/root/.kube/kubespray.conf
kubectl -n lab delete deploy,svc,pdb,hpa,netpol,servicemonitor,secret shop shop-db --all --ignore-not-found 2>/dev/null
kubectl create ns lab --dry-run=client -o yaml | kubectl apply -f -
command -v jq    # нужен для audit.sh
```

## Стартовая проверка

Убедитесь, что кластер доступен:
```bash
kubectl get nodes
```

---

## Часть 1: Аудит «наивного» приложения (ДО)

«Наивное» приложение `shop` (`broken/app.yaml`) — типичные анти-паттерны:
`nginx:latest`, 1 реплика, без resources/probes/securityContext (root), пароль в
открытом env.

```bash
kubectl -n lab apply -f broken/app.yaml
bash audit/audit.sh lab shop
```

> ✅ **Прогнано:** аудит даёт **11 [FAIL] из 11** — приложение НЕ прод-готово.
> Каждый FAIL — конкретный риск (один под = даунтайм при рестарте; root + нет
> securityContext = широкая поверхность атаки; `:latest` = неповторяемый деплой;
> пароль в env виден в `describe`/`inspect`; нет NetworkPolicy = всё открыто).

---

## Часть 2: Харденинг до прод-готовности (ПОСЛЕ)

`manifests/` чинит ВСЕ критерии. Ключевые приёмы:

```bash
# Секрет — отдельно (в проде: Sealed Secrets / ESO / Vault, см. модуль 16)
kubectl -n lab create secret generic shop-db --from-literal=password='S3cr3tP@ss'

kubectl -n lab apply -f manifests/      # app + pdb + hpa + netpol + servicemonitor
kubectl -n lab rollout status deploy/shop --timeout=120s
bash audit/audit.sh lab shop
```

> ✅ **Прогнано:** аудит даёт **0 провалов из 11 — ПРОД-ГОТОВО ✅**. Что изменилось:
> - `replicas: 2` + PDB(minAvailable 1) + topologySpread(hostname) — пережёвывает
>   потерю ноды/drain;
> - readiness+liveness на :8080; requests/limits (Burstable);
> - образ `nginxinc/nginx-unprivileged:1.27-alpine` (запиннен, non-root, :8080);
> - securityContext: runAsNonRoot/runAsUser 101/allowPrivilegeEscalation false/
>   **readOnlyRootFilesystem** (+ emptyDir на /var/cache/nginx,/var/run,/tmp)/
>   drop ALL/seccomp RuntimeDefault — проходит **PSA restricted**;
> - HPA 2→5 по 70% CPU; default-deny + allow-dns + allow-shop NetworkPolicy;
> - пароль через `secretKeyRef`; ServiceMonitor (label `release: kps`).

> ⚠️ **Честно:** nginx сам не отдаёт `/metrics` — ServiceMonitor проходит критерий
> «настроен», но для РЕАЛЬНЫХ метрик в прод добавляют sidecar
> `nginx-prometheus-exporter` (+ stub_status). Аудит проверяет НАЛИЧИЕ
> ServiceMonitor, не содержимое метрик.

---

## Аудит-инструмент (`audit/audit.sh`)

Переиспользуемый «гейт» прод-готовности для ЛЮБОГО Deployment:

```bash
bash audit/audit.sh <namespace> <deployment>     # default: lab shop
# печатает [PASS]/[FAIL] по 11 критериям; exit !=0 если есть провал
# -> можно встроить в CI как gate перед выкатом в прод
```

Проверяет (через `kubectl ... -o json | jq`): сам Deployment (replicas, probes,
resources, securityContext, image, env) + связанные объекты в namespace (PDB, HPA,
NetworkPolicy default-deny, ServiceMonitor).

---

## Проверка

```bash
bash verify/verify.sh
# == Итог: провалов 0 из 11 ==  ПРОД-ГОТОВО ✅
# [OK] production-readiness audit: 0 провалов (все 11 критериев)
# [OK] project-d verified
```

`verify.sh`: `Deployment/shop` готов → `audit.sh` без провалов → `[OK] project-d verified`.

---

## Финальная карта ресурсов

| Ресурс | Что демонстрирует |
|--------|-------------------|
| `broken/` | анти-паттерны (аудит = 11 FAIL) |
| `manifests/` | прод-готовое приложение (аудит = 0 FAIL) |
| `audit/audit.sh` | переиспользуемый аудит-гейт прод-готовности |

---

## Теоретические вопросы (итоговые)

1. Назовите 11 критериев прод-готовности и риск, который снимает каждый.
2. Почему `replicas: 1` + отсутствие PDB делает выкат/drain опасным?
3. Чем `readOnlyRootFilesystem` усложняет запуск nginx и как это решается?
4. Почему пароль в открытом `env` — утечка, и какие есть безопасные варианты (модуль 16)?
5. Как встроить `audit.sh` в CI как gate перед прод-деплоем?

---

## Практические задания (отработка)

> Делайте на кластере; проверяйте себя через `audit/audit.sh` (он покажет, что ещё не так).

1. **Сломай и почини по одному.** Возьмите `manifests/app.yaml`, уберите ОДИН
   критерий (напр. `readinessProbe`), примените, запустите `audit.sh` — убедитесь,
   что именно этот критерий стал `[FAIL]`. Верните. Повторите для resources,
   securityContext, образа.
2. **Свой 12-й критерий.** Добавьте в `audit.sh` проверку, что у Deployment задан
   `terminationGracePeriodSeconds` И в контейнере есть `lifecycle.preStop`
   (graceful shutdown, модуль 02). Сделайте so, чтобы приложение его проходило.
3. **Проверка PSA restricted вживую.** Создайте ns `prod-restricted` с
   `pod-security.kubernetes.io/enforce=restricted`, разверните туда `manifests/`-приложение
   — оно должно пройти admission. Затем разверните `broken/` — оно должно быть
   отклонено. Объясните по тексту ошибки, какие поля нарушены (модуль 14).
4. **selfHeal через PDB.** Сделайте `kubectl drain` worker-ноды (cordon+drain,
   модуль 10) и убедитесь по событиям, что PDB не дал увести обе реплики разом, а
   topologySpread развёл их по нодам. Верните ноду (`uncordon`).
5. **Аудит чужого приложения.** Запустите `audit.sh lab <любой-деплой>` против
   приложения из другого модуля (напр. `hpa-demo` из м11 или `web-a` из м22) и
   составьте список, что нужно добавить для прод-готовности.
6. **CI-gate (бонус).** Напишите обёртку, которая прогоняет `audit.sh` по ВСЕМ
   Deployment в namespace и падает (exit!=0), если хоть один не прод-готов —
   прототип «policy gate» в пайплайне.

---


## Чему вы научились

В этом модуле вы научились:
- Проведению аудита Production-Readiness
- Настройке PDB, проб и requests/limits для production
- Внедрению security-практик в деплойменты

## Уборка

```bash
kubectl -n lab delete -f manifests/ --ignore-not-found
kubectl -n lab delete -f broken/app.yaml --ignore-not-found
kubectl -n lab delete secret shop-db --ignore-not-found
```
