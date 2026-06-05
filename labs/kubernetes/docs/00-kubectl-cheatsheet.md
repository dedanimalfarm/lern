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
# Проверить статус Application
kubectl -n argocd get app <app-name>

# Форсировать синхронизацию вручную (если авто-синк выключен)
argocd app sync <app-name>

# Посмотреть сгенерированные Application из ApplicationSet
kubectl -n argocd get applicationsets
kubectl -n argocd get apps -l argocd.argoproj.io/instance=<appset-name>
```

## 4. Job и CronJob (Модуль 20)
```bash
# Запустить Job из CronJob вручную (для теста)
kubectl -n lab create job --from=cronjob/<cronjob-name> manual-run-1

# Дождаться завершения Job в скрипте
kubectl -n lab wait --for=condition=complete job/<job-name> --timeout=120s
```

## 5. SSL сертификаты и Ingress (Модуль 22, Capstone F)
```bash
# Проверить статус выпуска сертификата (cert-manager)
kubectl -n lab get certificate
kubectl -n lab describe certificate <cert-name>
kubectl -n lab get certificaterequests

# Проверить срок действия сертификата снаружи через openssl
echo | openssl s_client -showcerts -servername example.com -connect 10.10.0.10:443 2>/dev/null | openssl x509 -inform pem -noout -text | grep -A 2 "Validity"
```

## 6. Полезные трюки
```bash
# Форматирование вывода JSONPath
kubectl get pod <pod-name> -o jsonpath='{.status.podIP}'

# Перезапуск всех подов Deployment (Rolling Update)
kubectl -n lab rollout restart deployment/<deploy-name>

# Временный под для тестов DNS и сети (Busybox)
kubectl -n lab run test-net --image=busybox:1.36 --restart=Never -i --rm -- sh
```
