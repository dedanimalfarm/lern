# Сводный Troubleshooting Playbook

Этот справочник объединяет деревья диагностики (troubleshooting trees) из различных модулей лаборатории. Используйте его для системного подхода к поиску и устранению неисправностей.

## 1. Проблемы с запуском Подов (Модули 02, 06)

Если `kubectl get pods` показывает, что под не в состоянии `Running`:

### 1.1 Статус `Pending`
Под не может быть запланирован (запущен) на узле.
- **Действие:** `kubectl describe pod <pod-name>` (смотрите секцию Events).
- **Причина: Нет доступных узлов.** Слишком большие `requests` (CPU/Memory).
- **Причина: Taints/Tolerations.** На узле есть Taint (например, `node-role.kubernetes.io/control-plane:NoSchedule`), а у пода нет соответствующего Toleration.
- **Причина: NodeSelector/Affinity.** Под требует метку узла (например, `disktype=ssd`), которой ни у кого нет.
- **Причина: PVC Pending.** Под ожидает монтирования диска, но PersistentVolumeClaim не может связаться с PersistentVolume (см. Модуль 05/21).

### 1.2 Статус `CrashLoopBackOff` или `Error`
Контейнер запускается, но процесс внутри сразу завершается.
- **Действие:** `kubectl logs <pod-name>` или `kubectl logs <pod-name> --previous`.
- **Причина: Ошибка приложения.** Процесс падает с exit-кодом (например, синтаксическая ошибка в коде, паника).
- **Причина: Отсутствие конфигурации.** Приложению нужен ConfigMap/Secret, который не существует или не смонтирован по правильному пути.
- **Причина: OOMKilled (Out Of Memory).** Контейнер превысил свой `limit` по памяти и был убит ядром OOM Killer. Смотрите `kubectl describe pod` -> раздел State -> Reason: OOMKilled.

### 1.3 Статус `Init:CrashLoopBackOff`
Падает `initContainer`. Под не начнёт запуск основных контейнеров, пока все init-контейнеры не завершатся успешно.
- **Действие:** `kubectl logs <pod-name> -c <init-container-name>`.

## 2. Сетевые проблемы: "Нет связи" (Модуль 04, 15, F)

Приложение в статусе Running, но недоступно по сети.

### 2.1 Под недоступен через Service
- **Действие 1 (Проверка Endpoints):** `kubectl get endpoints <service-name>`. Если список пуст, значит Service не нашёл поды. Проверьте `matchLabels` в `Service` и `labels` у Пода.
- **Действие 2 (Проверка Readiness):** Если Endpoints пуст, но лейблы совпадают, проверьте Readiness-пробу (`kubectl describe pod`). Если проба падает, под исключается из балансировки Service.
- **Действие 3 (Проверка Портов):** Убедитесь, что `targetPort` в Service совпадает с портом, на котором слушает контейнер.

### 2.2 Ошибки разрешения имён (DNS)
- **Симптом:** `wget: bad address 'api'` или `nslookup api` возвращает SERVFAIL/NXDOMAIN.
- **Действие 1 (Проверка CoreDNS):** `kubectl -n kube-system get pods -l k8s-app=kube-dns`. Они должны быть Running.
- **Действие 2 (NetworkPolicy):** Убедитесь, что egress-трафик по UDP порту 53 (к CoreDNS) не заблокирован правилами `NetworkPolicy` (см. Модуль 15).
- **Действие 3:** Попробуйте сделать пинг или запрос напрямую по IP-адресу Service (`ClusterIP`). Если по IP работает, а по имени нет — проблема в DNS.

## 3. Проблемы с хранилищем (Модули 05, 21)

- **Симптом:** PVC висит в статусе `Pending`.
- **Действие:** `kubectl describe pvc <pvc-name>`.
- **Причина:** Указан несуществующий `storageClassName`. Если не указан, проверьте наличие дефолтного StorageClass (`kubectl get sc`).
- **Причина:** Storage-провайдер (CSI) не может динамически выделить том. Проверьте логи CSI-драйвера (например, `local-path-provisioner`).

## 4. Проблемы с политиками и безопасностью (Модуль 14, E)

- **Симптом:** Манифест не применяется, `kubectl apply` возвращает ошибку `Forbidden`.
- **Причина (Pod Security Admission):** Namespace настроен на стандарт `restricted` (`pod-security.kubernetes.io/enforce: restricted`), а вы пытаетесь запустить под с `runAsUser: 0` (root) или включёнными privilege escalation.
  - **Решение:** Добавьте `securityContext` в манифест пода, соответствующий стандарту Restricted.
- **Причина (ValidatingAdmissionPolicy):** Сработало кастомное правило VAP (например, запрет использования тега `:latest`).
  - **Решение:** Исправьте манифест так, чтобы он соответствовал правилу (например, используйте явный тег `:v1.2.3`).

## 5. Универсальный алгоритм (Триаж инцидента - Project F)

1. **Оцените масштаб:** Проблема с одним приложением (namespace) или со всем кластером (Node, DNS, Ingress)? `kubectl get nodes`, `kubectl get pods -A | grep -v Running`.
2. **Проверьте события:** `kubectl get events --sort-by='.metadata.creationTimestamp' | tail -n 20`.
3. **Идите снизу вверх (по модели OSI):**
   - Узлы здоровы? (Taints, NotReady).
   - Поды живы? (CrashLoop, Pending).
   - Поды проходят Readiness? (Endpoints).
   - Имена резолвятся? (DNS).
   - Трафик доходит извне? (Ingress).
4. **Читайте логи:** И системных компонентов (CoreDNS, Ingress Controller), и самого приложения.
