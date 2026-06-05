# Project E: Secure Multi-Tenant Platform (защищённая мульти-тенант платформа)

Цель: собрать платформу, где НЕСКОЛЬКО команд (тенантов) делят один кластер, но
надёжно изолированы друг от друга. Это СИНТЕЗ слоя безопасности всей лабы: каждый
тенант ограничен по тому, ЧТО он может запускать (PSA), С КЕМ общаться
(NetworkPolicy), ЧЕМ управлять (RBAC), СКОЛЬКО ресурсов брать (Quota/LimitRange),
плюс общий guard policy-as-code (VAP). В центре — переиспользуемый
`audit/isolation-audit.sh`, ставящий [PASS]/[FAIL] по 6 контролям изоляции.

> Опирается на Calico (реальный enforcement NetworkPolicy) — есть на нашем
> Kubespray. PSA/RBAC/Quota/VAP — встроены в k8s, аддонов не требуют.

> Синтезирует модули: 06 (ResourceQuota/LimitRange), 07 (RBAC/securityContext),
> 12 (limits/QoS), 14 (PSA + ValidatingAdmissionPolicy), 15 (NetworkPolicy
> микросегментация). Каждый — кирпич; здесь они складываются в платформу.

---

## Архитектура изоляции

Два тенанта (`tenant-a`, `tenant-b`) на общем кластере. Пять независимых слоёв:

```
                       ┌─────────────── tenant-a ───────────────┐  ┌──── tenant-b ────┐
  PSA restricted ─────►│ только non-root/drop-caps/seccomp поды   │  │ (то же самое)    │
  NetworkPolicy ──────►│ default-deny + DNS + intra; НЕТ к tenant-b│ ✗ │◄── НЕТ к tenant-a│
  RBAC ───────────────►│ SA tenant-a-deployer: только ЭТОТ ns      │  │ свой SA, свой ns │
  Quota + LimitRange ─►│ cpu/mem/pods/services потолки             │  │ свои потолки     │
  hardened web (2x)    │ nginx-unprivileged :8080, ROfs, drop ALL  │  │ web (2x)         │
                       └─────────────────────────────────────────┘  └──────────────────┘
  policy-as-code (VAP no-latest) ── нацелен на namespaces с меткой platform-tenant=true
                                    (НЕ на lab/прочие — изоляция политики)
```

---

## Предварительные требования

```bash
export KUBECONFIG=/root/.kube/kubespray.conf   # Kubespray + Calico
command -v jq >/dev/null || echo "нужен jq для аудита"
```

---

## Развёртывание

```bash
kubectl apply -f manifests/tenant-a.yaml
kubectl apply -f manifests/tenant-b.yaml
kubectl apply -f manifests/policy/vap-no-latest.yaml

kubectl -n tenant-a rollout status deploy/web --timeout=90s
kubectl -n tenant-b rollout status deploy/web --timeout=90s
# оба web — по 2 пода Running (hardened-образ прошёл restricted PSA)
```

---

## Доказательства изоляции (5 проверок)

Платформа считается безопасной, только если КАЖДЫЙ механизм реально срабатывает.
Ниже — прогон на нашем кластере (вывод реальный).

### 1. PSA: небезопасный под отклоняется

```bash
kubectl -n tenant-a run bad-priv --image=busybox:1.36 --restart=Never --privileged \
  --command -- sleep 60
# Error from server (Forbidden): pods "bad-priv" is forbidden:
#   violates PodSecurity "restricted:latest": privileged (...must not set privileged=true),
#   allowPrivilegeEscalation != false, unrestricted capabilities (...drop=["ALL"]),
#   runAsNonRoot != true, seccompProfile (...RuntimeDefault)
```
Привилегированный под не пройдёт — namespace помечен `enforce=restricted`.

### 2. policy-as-code (VAP): `:latest` запрещён — НО только у тенантов

```bash
# В тенанте — ОТКЛОНЕНО:
kubectl -n tenant-a create deploy bad-latest --image=nginx:latest
# deployments.apps "bad-latest" is forbidden: ValidatingAdmissionPolicy
#   'tenant-no-latest-tag' denied request: образы с тегом ':latest' ... запрещены

# В lab — РАЗРЕШЕНО (биндинг нацелен на platform-tenant=true, не на lab):
kubectl -n lab create deploy probe-latest --image=nginx:latest   # created
kubectl -n lab delete deploy probe-latest
```
Политика изолирована меткой namespace — не «протекает» в другие окружения.

### 3. RBAC: тенант управляет ТОЛЬКО своим namespace

```bash
kubectl auth can-i list pods -n tenant-a --as=system:serviceaccount:tenant-a:tenant-a-deployer
# yes
kubectl auth can-i list pods -n tenant-b --as=system:serviceaccount:tenant-a:tenant-a-deployer
# no        <- в чужой namespace доступа нет
```

### 4. ResourceQuota: нельзя выйти за лимиты

```bash
# count/services=5; создаём до лимита, 6-й отклоняется:
kubectl -n tenant-a create service clusterip svc6 --tcp=80:80
# services "svc6" is forbidden: exceeded quota: tenant-a-quota,
#   requested: count/services=1, used: count/services=5, limited: count/services=5
```

### 5. NetworkPolicy: тенанты не видят друг друга по сети

```bash
POD=$(kubectl -n tenant-a get pod -l app=web -o name | head -1)
# Cross-tenant — ЗАБЛОКИРОВАНО (default-deny egress пускает только DNS + свой ns):
kubectl -n tenant-a exec "$POD" -- wget -qO- --timeout=5 http://web.tenant-b.svc.cluster.local
# wget: download timed out                <- блок
# Внутри своего тенанта — РАБОТАЕТ:
kubectl -n tenant-a exec "$POD" -- wget -qO- --timeout=5 http://web.tenant-a.svc.cluster.local
# <!DOCTYPE html>... Welcome to nginx     <- доступ
```

---

## Аудит изоляции (переиспользуемый гейт)

`audit/isolation-audit.sh` проверяет 6 контролей для любого namespace-тенанта:

```bash
bash audit/isolation-audit.sh tenant-a
# == Аудит изоляции тенанта: tenant-a ==
#   [PASS] PSA enforce=restricted
#   [PASS] default-deny NetworkPolicy (Ingress+Egress)
#   [PASS] allow-dns NetworkPolicy присутствует
#   [PASS] ResourceQuota + LimitRange заданы
#   [PASS] RBAC: SA видит свой ns (yes), не чужой tenant-b (no)
#   [PASS] VAP no-latest-tag binding активен
#   ИТОГ: все контроли изоляции на месте для tenant-a
```

Код возврата ≠0 при любом провале — годится как CI-гейт онбординга нового тенанта.

---

## Проверка проекта

```bash
bash verify/verify.sh
# [OK] tenant-a: hardened web развёрнут (прошёл restricted PSA)
# [OK] tenant-b: hardened web развёрнут (прошёл restricted PSA)
# [OK] VAP tenant-no-latest-tag присутствует
# [OK] isolation-audit пройден для tenant-a (6/6 контролей)
# [OK] isolation-audit пройден для tenant-b (6/6 контролей)
# [OK] project-e secure-platform verified
```

---

## Карта ресурсов

| Слой | Ресурс | Модуль |
|------|--------|--------|
| Что запускать | Namespace label PSA `enforce=restricted` | 14 |
| С кем общаться | NetworkPolicy default-deny + allow-dns + allow-intra | 15 |
| Чем управлять | ServiceAccount + Role (own-ns) + RoleBinding | 07 |
| Сколько ресурсов | ResourceQuota + LimitRange | 06, 12 |
| Workload | hardened `web` (nginx-unprivileged, restricted) | 02, 07 |
| Общий guard | ValidatingAdmissionPolicy no-latest + binding | 14 |

---

## Практические задания (отработка)

1. Заведите ТРЕТИЙ тенант `tenant-c`: скопируйте `tenant-a.yaml`, замените имена
   (`sed 's/tenant-a/tenant-c/g'`), примените, прогоните `isolation-audit.sh tenant-c`.
2. Докажите cross-tenant блок в обе стороны (из tenant-b в tenant-a тоже timeout).
3. Попробуйте развернуть НЕ-hardened под в тенанте — получите список нарушений PSA;
   приведите его в соответствие по подсказкам ошибки.
4. Расширьте VAP: запретите ещё и `hostPath`-тома (добавьте `validations`-правило на
   CEL) и проверьте, что обычный том проходит, а hostPath — нет.
5. Ужесточите квоту tenant-a до `pods: "3"` и посмотрите, как 4-й под (scale web до 4)
   упрётся в `exceeded quota` на уровне ReplicaSet (событие FailedCreate).

---

## Уборка

```bash
kubectl delete -f manifests/policy/vap-no-latest.yaml --ignore-not-found
kubectl delete ns tenant-a tenant-b --ignore-not-found
# (namespace уносит за собой все ресурсы тенанта)
```

> ⚠️ VAP cluster-scoped — `vap-no-latest.yaml` надо удалить отдельно (namespace его
> не уносит). Биндинг нацелен на `platform-tenant=true`, поэтому пока он жив, любой
> новый namespace с этой меткой попадёт под запрет `:latest`.
