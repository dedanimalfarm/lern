# Project F (project-c): Incident Response — диагностика и устранение инцидентов

Цель: отработать РЕАКЦИЮ НА ИНЦИДЕНТ — по симптому быстро локализовать причину и
устранить. Это capstone-синтез всех деревьев диагностики лабы: от падающего пода
до сломанного GitOps и протухшего сертификата. В центре — переиспользуемый
`triage/incident-triage.sh`, который по симптому пода выдаёт диагноз, вероятную
причину и первую команду.

> Опирается на Calico (NetworkPolicy для DNS-инцидента) и Argo CD (sync-fail) —
> есть на нашем Kubespray. Базовые сценарии работают на любом кластере.

> Этот проект — расширение `project-c-broken-cluster-lab` до полноценного
> incident-response (ROADMAP capstone F). Базовые 4 сценария — в `broken/README.md`.

---

## Методология (один цикл на любой инцидент)

```
1. ЗАФИКСИРОВАТЬ симптом   →  kubectl get pods / get application / get events
2. ЛОКАЛИЗОВАТЬ            →  triage/incident-triage.sh (или дерево ниже)
3. ПОДТВЕРДИТЬ причину     →  describe / logs --previous / lastState / openssl
4. УСТРАНИТЬ               →  применить solution
5. ПРОВЕРИТЬ восстановление→  rollout status / endpoints / повторный триаж
```

---

## Каталог инцидентов

| # | Сценарий | Файл | Класс | Модуль |
|---|----------|------|-------|--------|
| 1 | CrashLoopBackOff | `broken/auth-service.yaml` | под падает (exit 1) | 02 |
| 2 | Readiness fail | `broken/catalog-api.yaml` | Running, 0/1, нет Endpoints | 02 |
| 3 | ImagePullBackOff | `broken/payment-worker.yaml` | образ не тянется | 01/03 |
| 4 | OOMKilled | `broken/report-generator.yaml` | exit 137, лимит памяти | 02/12 |
| 5 | **DNS failure** | `broken/dns-failure.yaml` | Running, резолв падает | 04/15 |
| 6 | **Pending/scheduling** | `broken/scheduling-pending.yaml` | под не размещается | 06/13 |
| 7 | **GitOps sync-fail** | `broken/sync-fail.yaml` | Argo OutOfSync/Unknown | 09/25 |
| 8 | **Cert-expiry** | `broken/cert-expiry/setup.sh` | TLS «тихо» сломан | 22 |

Сценарии 1–4 (детально, с подсказками) — в `broken/README.md`. Ниже — новые 5–8.

---

## Дерево триажа (по симптому)

```
Симптом
│
├─ Pod Pending ───────────► Insufficient/taint/PVC → Сценарий 6 (scheduling)
├─ ImagePullBackOff ──────► тег/реестр/секрет → Сценарий 3
├─ CrashLoopBackOff ──────► lastState OOMKilled? → Сценарий 4; иначе exit code → Сценарий 1
├─ Running, 0/1 NotReady ─► readinessProbe → Сценарий 2
├─ Running, 1/1, но «не работает»:
│     ├─ в логах bad address/timeout → Сценарий 5 (DNS/NetworkPolicy)
│     └─ TLS-ошибка у клиента, под жив → Сценарий 8 (cert-expiry)
└─ Argo Application не Synced ───────► path/repo/permission → Сценарий 7 (sync-fail)
```

Или просто — авто-триаж: `bash triage/incident-triage.sh <ns> <label>`.

---

## Сценарий 5: DNS failure

```bash
kubectl -n lab apply -f broken/dns-failure.yaml
kubectl -n lab logs -l app=dns-client --tail=3
# ;; connection timed out; no servers could be reached
# RESOLVE_FAIL                       <- приложение не резолвит DNS
```

**Триаж:**
```bash
bash triage/incident-triage.sh lab app=dns-client
# ДИАГНОЗ: под Running, но в логах ошибки РЕЗОЛВА/сети
# ПРИЧИНА: DNS/egress закрыт NetworkPolicy (нет allow-dns) ...
```
Причина: NetworkPolicy `dns-client-deny` закрыла egress целиком, allow-dns нет.
На Kubespray резолвер — nodelocaldns (link-local 169.254.25.10), поэтому в фикс
нужен и `ipBlock 169.254.25.10/32`, не только namespaceSelector kube-system.

**Решение:**
```bash
kubectl -n lab apply -f solutions/dns-failure-fixed.yaml
kubectl -n lab logs -l app=dns-client --tail=2   # снова резолвит
kubectl -n lab delete deploy dns-client; kubectl -n lab delete netpol --all
```

---

## Сценарий 6: Pending — под не размещается

```bash
kubectl -n lab apply -f broken/scheduling-pending.yaml
kubectl -n lab get pods -l app=heavy-compute      # Pending навсегда
bash triage/incident-triage.sh lab app=heavy-compute
# ДИАГНОЗ: Pending — scheduler не разместил под
# ПРИЧИНА: не хватает ресурсов на нодах (requests > свободного)
# (FailedScheduling: 0/3 nodes available: 2 Insufficient cpu, 1 untolerated taint)
```
Причина: `requests.cpu: 8` — ни одна нода столько не даёт (worker'ы ~1.4 CPU).

**Решение:** привести requests к реальной ёмкости.
```bash
kubectl -n lab apply -f solutions/scheduling-pending-fixed.yaml
kubectl -n lab rollout status deploy/heavy-compute --timeout=60s
kubectl -n lab delete deploy heavy-compute
```

---

## Сценарий 7: GitOps sync-fail (Argo CD)

```bash
kubectl apply -f broken/sync-fail.yaml
kubectl -n argocd get application incident-app \
  -o jsonpath='sync={.status.sync.status} msg={.status.conditions[*].message}{"\n"}'
# sync=Unknown msg=... ".../bas": app path does not exist
```
Причина: опечатка в `source.path` (`bas` вместо `base`) — Argo не находит манифесты.

**Решение:** исправить path и переприменить.
```bash
kubectl apply -f solutions/sync-fail-fixed.yaml
kubectl -n argocd get application incident-app \
  -o jsonpath='sync={.status.sync.status} health={.status.health.status}{"\n"}'
# sync=Synced health=Healthy
kubectl -n argocd delete application incident-app   # уборка
kubectl -n lab delete deploy web --ignore-not-found; kubectl -n lab delete svc web --ignore-not-found
```

---

## Сценарий 8: Cert-expiry (протухший TLS)

Самый коварный класс: под жив и Ready, но TLS-хендшейк падает у клиента —
в статусе пода НИЧЕГО не видно. Диагностика — проверять СРОК сертификата.

```bash
bash broken/cert-expiry/setup.sh lab          # создаёт Secret web-tls с cert из 2024
# Диагностика — срок и checkend:
kubectl -n lab get secret web-tls -o jsonpath='{.data.tls\.crt}' \
  | base64 -d | openssl x509 -noout -enddate -checkend 0
# notAfter=Jan  2 00:00:00 2024 GMT
# Certificate will expire        <- checkend 0 => уже просрочен
```

**Решение:** перевыпустить сертификат (в проде это делает cert-manager, модуль 22).
```bash
bash solutions/cert-expiry-fixed.sh lab        # обновляет Secret валидным cert
kubectl -n lab delete secret web-tls
```

---

## Авто-триаж — `triage/incident-triage.sh`

Классифицирует под по фазе/waiting/lastState/events/логам и печатает диагноз +
причину + первую команду. Синтез деревьев модулей 02/04/05/06/08.

```bash
bash triage/incident-triage.sh lab app=report-generator
# == Триаж: ns/lab pod/report-generator-... ==
#    phase=Running ... lastState=OOMKilled(exit 137)
# ДИАГНОЗ: CrashLoop из-за OOMKilled (exit 137)
# ПРИЧИНА: контейнер превышает limits.memory. Модуль 02/12.
# ПЕРВАЯ КОМАНДА: kubectl ... lastState.terminated
```

---

## Проверка проекта

```bash
bash verify/verify.sh
# [OK] все 8 solution-файлов на месте (4 базовых + 4 новых)
# [OK] новые сценарии (dns/scheduling/sync/cert) + триаж-инструмент на месте
# [OK] project C verify script executed
```

---

## Практические задания (отработка)

1. Разверните любой broken-сценарий ВСЛЕПУЮ (не глядя в манифест) и локализуйте
   причину только через `triage/incident-triage.sh` + `describe`.
2. Сценарий 5: добавьте allow-dns ТОЛЬКО по namespaceSelector (без ipBlock) и
   убедитесь, что на Kubespray DNS всё равно не резолвит — докажите роль nodelocaldns.
3. Сценарий 6: вместо снижения requests — затолерируйте под на control-plane
   (toleration) и посмотрите, сядет ли он туда.
4. Сценарий 8: смонтируйте `web-tls` в под как том и убедитесь, что k8s НЕ
   проверяет срок cert при монтировании (протухший монтируется молча).
5. Расширьте `incident-triage.sh`: добавьте ветку для `Evicted` (по `status.reason`).

---

## Уборка

```bash
kubectl -n lab delete deploy dns-client heavy-compute web --ignore-not-found
kubectl -n lab delete netpol --all --ignore-not-found
kubectl -n lab delete secret web-tls --ignore-not-found
kubectl -n argocd delete application incident-app --ignore-not-found
```

> Capstone F закрывает цикл: лаба учит СТРОИТЬ (модули) и ЭКСПЛУАТИРОВАТЬ
> (diagnose → fix). Деревья диагностики из модулей здесь собраны в один runbook.
