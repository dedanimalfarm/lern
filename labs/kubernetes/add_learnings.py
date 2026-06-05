import os
import re
import glob

learnings = {
    "01-kubectl-basics": "- Базовым операциям с kubectl (get, describe, logs)\n- Пониманию архитектуры API Kubernetes\n- Императивному созданию ресурсов",
    "02-pods-lifecycle": "- Настройке Liveness и Readiness проб\n- Использованию InitContainers для подготовки окружения\n- Анализу причин перезапусков подов (OOMKilled, CrashLoopBackOff)",
    "03-workloads": "- Разнице между Deployment, DaemonSet и StatefulSet\n- Использованию Job и CronJob для разовых задач\n- Пониманию стратегий обновления (RollingUpdate)",
    "04-networking": "- Балансировке трафика через Service (ClusterIP, NodePort)\n- Настройке L7 маршрутизации через Ingress\n- Диагностике DNS внутри кластера (CoreDNS)",
    "05-storage": "- Разнице между ephemeral хранилищами (emptyDir) и постоянными (PV/PVC)\n- Динамическому выделению хранилища через StorageClass\n- Подключению блочных дисков к StatefulSet",
    "06-scheduling": "- Использованию NodeSelector и NodeAffinity для привязки подов к узлам\n- Механизмам отталкивания Taint и Toleration\n- Пониманию работы kube-scheduler",
    "07-config-security": "- Передаче конфигураций через ConfigMap и секретов через Secret\n- Настройке ServiceAccount и политик доступа RBAC\n- Ограничению прав процессов через SecurityContext",
    "08-observability": "- Чтению и анализу логов контейнеров\n- Работе с Events Kubernetes для диагностики проблем\n- Пониманию концепций метрик и трейсинга",
    "09-helm-gitops": "- Упаковке приложений в Helm-чарты\n- Декларативному деплою через Argo CD (GitOps)\n- Управлению конфигурациями с Kustomize",
    "10-kubeadm-admin": "- Базовому администрированию control-plane\n- Добавлению узлов в кластер\n- Диагностике системных компонентов (kube-proxy, kubelet)",
    "11-autoscaling": "- Настройке горизонтального автомасштабирования (HPA)\n- Пониманию работы Cluster Autoscaler\n- Сбору custom-метрик для масштабирования",
    "12-resource-management": "- Использованию Requests и Limits для управления ресурсами\n- Пониманию классов обслуживания QoS (Guaranteed, Burstable)\n- Настройке PriorityClasses для вытеснения (preemption) подов",
    "13-resilience": "- Распределению подов по зонам отказа (TopologySpreadConstraints)\n- Использованию PodDisruptionBudget (PDB) для безопасных обновлений\n- Анти-аффинити (Anti-Affinity) для отказоустойчивости",
    "14-pod-security-admission": "- Настройке стандартов безопасности (Pod Security Standards)\n- Использованию ValidatingAdmissionPolicy для кастомных правил\n- Защите кластера от привилегированных подов",
    "15-network-policy-enforced": "- Реализации микросегментации через NetworkPolicy\n- Концепции Zero-Trust в кластере (default-deny)\n- Разрешению специфичного Ingress/Egress трафика",
    "16-secrets-management": "- Шифрованию секретов в etcd (encryption-at-rest)\n- Использованию Sealed Secrets для хранения секретов в Git\n- Интеграции с внешними хранилищами через External Secrets Operator",
    "17-metrics-alerting": "- Развёртыванию kube-prometheus-stack\n- Сбору метрик приложений через ServiceMonitor\n- Настройке правил алертинга в Prometheus/Alertmanager",
    "18-logs-tracing": "- Развёртыванию стека логирования Loki + Promtail\n- Работе с LogQL для запросов по логам\n- Диагностике конфигурации агентов сбора логов",
    "19-crd-operators": "- Расширению Kubernetes API через CustomResourceDefinition\n- Пониманию паттерна Operator/Controller\n- Управлению кастомными ресурсами через kubectl",
    "20-batch-workflows": "- Запуску параллельных и индексированных (Indexed) Job\n- Настройке политик обработки ошибок (podFailurePolicy)\n- Периодическим бэкапам и батч-задачам через CronJob",
    "21-stateful-systems": "- Управлению базами данных с помощью операторов (CloudNativePG)\n- Разнице между оператором и ручным StatefulSet\n- Механизмам Failover и High Availability в БД на Kubernetes",
    "22-ingress-tls": "- Установке Ingress-контроллера (NGINX)\n- Автоматическому выпуску SSL-сертификатов через cert-manager\n- Настройке HTTP(S) маршрутизации",
    "25-gitops-at-scale": "- Управлению множеством окружений (multi-env) через Kustomize\n- Массовому деплою с помощью Argo CD ApplicationSet\n- Структурированию репозитория для GitOps",
    "project-a-platform-namespace": "- Сборке комплексного окружения с квотами и RBAC\n- Интеграции различных Kubernetes-объектов воедино\n- Подготовке tenant-namespace",
    "project-b-stateful-service": "- Деплою stateful-приложений с постоянным хранилищем\n- Настройке сетевого взаимодействия между компонентами\n- Решению проблем персистентности данных",
    "project-c-broken-cluster-lab": "- Системному траблшутингу кластера Kubernetes\n- Чтению логов системных компонентов (kubelet, coredns)\n- Восстановлению после отказа сертификатов и DNS",
    "project-d-production-readiness": "- Проведению аудита Production-Readiness\n- Настройке PDB, проб и requests/limits для production\n- Внедрению security-практик в деплойменты",
    "project-e-secure-platform": "- Построению защищённой мульти-тенант платформы\n- Настройке изоляции через NetworkPolicy и PSA\n- Внедрению VAP для предотвращения плохих практик (например, тега :latest)"
}

def process_file(path, mod_name):
    if mod_name not in learnings: return
    with open(path, 'r') as f:
        content = f.read()
    
    if "## Чему вы научились" in content:
        return
        
    learning_block = f"\n## Чему вы научились\n\nВ этом модуле вы научились:\n{learnings[mod_name]}\n"
    
    # Insert before "Уборка" or at the end
    if "## Уборка" in content:
        content = content.replace("## Уборка", learning_block + "\n## Уборка")
    else:
        content += learning_block
        
    with open(path, 'w') as f:
        f.write(content)

for f in sorted(glob.glob('modules/*/README.md') + glob.glob('projects/*/README.md')):
    mod_name = os.path.basename(os.path.dirname(f))
    process_file(f, mod_name)
