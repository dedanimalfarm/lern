# Инцидент: Ingress без ADDRESS, маршрут не работает

`kubectl -n lab apply -f broken/scenario-01/ingress.yaml` создаёт Ingress
`broken-routing` с `ingressClassName: nginx-does-not-exist`.

## Симптом
- `kubectl -n lab get ingress broken-routing` — колонка **ADDRESS пуста** (в отличие
  от рабочих Ingress, у которых там internal-IP ноды).
- `curl --resolve broken.lab.local:80:<CIP> http://broken.lab.local/` -> `404`
  (default backend): наш контроллер этот Ingress не обслуживает.

## Диагностика
```bash
kubectl get ingressclass                      # какие классы РЕАЛЬНО есть (у нас: nginx)
kubectl -n lab get ingress broken-routing -o jsonpath='{.spec.ingressClassName}{"\n"}'
# nginx-does-not-exist   <- класса с таким именем нет -> контроллер игнорирует Ingress
```

## Причина
`ingressClassName` должен совпадать с именем установленного `IngressClass`. Контроллер
обслуживает ТОЛЬКО свои Ingress (по классу). Неверный/несуществующий класс = Ingress
«ничей».

## Решение
`solutions/01-wrong-class/ingress.yaml` — тот же Ingress с `ingressClassName: nginx`.
