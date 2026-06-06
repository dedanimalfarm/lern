# Шпаргалка по командам (Kubectl Cheatsheet)

## 1. Базовые операции (Поды, Deployment, Service)
```bash
# Получить все ресурсы в namespace
kubectl -n lab get all

# Посмотреть расширенный статус подов (включая IP и Node)
kubectl -n lab get pods -o wide

# Посмотреть детали объекта и его Events
kubectl -n lab describe pod <pod-name>

# Чтение логов (с хвоста)
kubectl -n lab logs <pod-name> --tail=200

# Выполнение команды внутри контейнера
kubectl -n lab exec -it <pod-name> -- sh
```

## 2. Kustomize (Модуль 25)
Kustomize встроен в kubectl (начиная с версии 1.14).
```bash
# Просмотр результирующих манифестов (сборка) без применения
kubectl kustomize overlays/prod

# Применение манифестов через kustomize
kubectl apply -k overlays/prod

# Удаление ресурсов
kubectl delete -k overlays/prod
```

## 3. Argo CD и GitOps (Модули 09, 25)
Хотя у Argo CD есть свой CLI и UI, многие вещи можно делать через kubectl.
```bash
# Проверить состояние Application и фазу синхронизации
kubectl -n argocd get app <app-name> -o custom-columns=NAME:.metadata.name,SYNC_STATUS:.status.sync.status,HEALTH:.status.health.status

# Форсировать синхронизацию вручную (если авто-синк выключен)
argocd app sync <app-name>

# Посмотреть детали ошибки синхронизации
kubectl -n argocd get app <app-name> -o yaml | grep -A 10 "message:"

# Посмотреть сгенерированные Application из ApplicationSet
kubectl -n argocd get applicationsets
kubectl -n argocd get apps -l argocd.argoproj.io/instance=<appset-name>
```

## 4. Job и CronJob (Модуль 20)
```bash
# Запустить Job из CronJob вручную (для теста)
kubectl -n lab create job --from=cronjob/<cronjob-name> manual-run-1

# Проверить статус выполнения Job (сколько выполнено, сколько осталось)
kubectl -n lab get job <job-name> -o custom-columns=NAME:.metadata.name,COMPLETIONS:.status.succeeded,FAILED:.status.failed

# Дождаться завершения Job в скрипте
kubectl -n lab wait --for=condition=complete job/<job-name> --timeout=120s
```

## 5. SSL сертификаты и Ingress / cert-manager (Модуль 22, Capstone F)
```bash
# Проверить статус выпуска сертификата (cert-manager)
kubectl -n lab get certificate
kubectl -n lab describe certificate <cert-name>

# Отладка цепочки выпуска сертификата (Certificate -> CertificateRequest -> Order -> Challenge)
kubectl -n lab get certificaterequests
kubectl -n lab describe order <order-name>
kubectl -n lab describe challenge <challenge-name>

# Проверить срок действия сертификата снаружи через openssl
echo | openssl s_client -showcerts -servername example.com -connect 10.10.0.10:443 2>/dev/null | openssl x509 -inform pem -noout -text | grep -A 2 "Validity"
```

## 6. ValidatingAdmissionPolicy (VAP) (Модуль 14)
```bash
# Посмотреть все активные политики и их привязки
kubectl get validatingadmissionpolicies
kubectl get validatingadmissionpolicybindings

# Узнать, какая политика блокирует создание ресурса (в случае ошибки)
# Обычно это видно в самом сообщении об ошибке, но можно проверить Audit лог (если включен)
# или временно перевести политику в режим Audit:
kubectl patch validatingadmissionpolicy <policy-name> --type='json' -p='[{"op": "replace", "path": "/spec/validationActions", "value": ["Audit", "Warn"]}]'

# Проверить селекторы привязки политики
kubectl get validatingadmissionpolicybinding <binding-name> -o yaml | grep -A 5 "matchResources"
```

## 7. Отладка NetworkPolicy (Модули 15, Project E)
```bash
# Посмотреть все политики в namespace
kubectl -n lab get networkpolicy

# Проверить, какие поды попадают под действие политики (matchLabels)
kubectl -n lab describe networkpolicy <policy-name> | grep -A 5 "PodSelector"

# Запустить под в нужном namespace с нужными лейблами для проверки связности
kubectl -n lab run test-client --image=curlimages/curl --labels="role=frontend" -it --rm -- sh
```

## 8. HPA (Horizontal Pod Autoscaler) (Модуль 11)
```bash
# Посмотреть текущую загрузку и количество реплик
kubectl -n lab get hpa

# Если HPA показывает <unknown>/<unknown>, проверить метрики подов
kubectl -n lab top pods

# Детально посмотреть события HPA (почему не скейлится)
kubectl -n lab describe hpa <hpa-name> | grep -A 10 "Events"
```

## 9. Полезные трюки
```bash
# Форматирование вывода JSONPath
kubectl get pod <pod-name> -o jsonpath='{.status.podIP}'

# Перезапуск всех подов Deployment (Rolling Update)
kubectl -n lab rollout restart deployment/<deploy-name>

# Временный под для тестов DNS и сети (Busybox)
kubectl -n lab run test-net --image=busybox:1.36 --restart=Never -i --rm -- sh
```
