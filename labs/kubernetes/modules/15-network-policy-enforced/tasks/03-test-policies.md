# 03-test-policies

## Задача
Научиться ТЕСТИРОВАТЬ NetworkPolicy (а не верить на слово).

## Метод
Запускать одноразовые поды с нужными labels и проверять связность `wget`:

```bash
# из пода-«web» (label app=web) к api -> ожидаем OK
kubectl -n lab run probe-web --labels app=web --image=busybox:1.36 --restart=Never -i --rm -- \
  wget -qO- --timeout=4 http://api | head -1
# из пода-«web» к db -> ожидаем БЛОК (timeout)
kubectl -n lab run probe-web --labels app=web --image=busybox:1.36 --restart=Never -i --rm -- \
  wget -qO- --timeout=4 http://db
```

## Проверка
- Связность совпадает с матрицей политик; запрещённые пути дают timeout.
