# 02 — Sealed Secrets: секрет, который можно коммитить

## Задача
Запечатать секрет через `kubeseal`, применить `SealedSecret` и доказать, что расшифровать
его может только контроллер этого кластера.

## Проверка
```bash
kubectl -n lab create secret generic app-creds \
  --from-literal=username=appuser --from-literal=password='S3cr3tP@ss' \
  --dry-run=client -o yaml \
  | kubeseal --controller-namespace kube-system -o yaml > /tmp/sealed-secret.yaml
grep -c 'AgB' /tmp/sealed-secret.yaml
kubectl apply -f /tmp/sealed-secret.yaml
kubectl -n lab get sealedsecret,secret app-creds
kubectl -n lab get secret app-creds -o jsonpath='{.data.password}' | base64 -d; echo
kubectl -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key -o name
```

## Ожидаемый результат
- `SealedSecret/app-creds` создан, через несколько секунд рядом появился обычный
  `Secret/app-creds`, пароль расшифрован в `S3cr3tP@ss`.
- В `encryptedData` только шифртекст (`AgB...`) — файл безопасно класть в git.
- Вы показали, где живёт приватный ключ контроллера (Secret с меткой
  `sealedsecrets.bitnami.com/sealed-secrets-key` в `kube-system`), и объяснили, почему
  `manifests/sealed/sealed-secret.yaml` из репозитория на чужом кластере даст
  `no key could decrypt secret` (Инцидент 1) и как это лечится (`kubeseal --re-encrypt`
  или перегенерация).
