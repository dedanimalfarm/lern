#!/usr/bin/env bash
# Сценарий со сломанным namespace: Разработчик жалуется, что его поды зависли в статусе Pending или получают ошибку "failed quota: platform-quota"

# 1. Применим сломанный манифест (без LimitRange)
kubectl apply -f manifests/namespace.yaml
kubectl apply -f manifests/quota.yaml
# Преднамеренно не применяем LimitRange

# 2. Разработчик пытается создать Pod без явных requests/limits
cat << 'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: demo-app
  namespace: platform
spec:
  containers:
  - name: nginx
    image: nginx:1.24-alpine
EOF

# Ожидаемый результат:
# Error from server (Forbidden): error when creating "STDIN": pods "demo-app" is forbidden: failed quota: platform-quota: must specify limits.cpu for: nginx; limits.memory for: nginx; requests.cpu for: nginx; requests.memory for: nginx

# 3. Как чинить (Решение):
# Нужно применить LimitRange, который добавит лимиты по умолчанию
# kubectl apply -f manifests/limitrange.yaml
# После этого создание пода пройдет успешно
