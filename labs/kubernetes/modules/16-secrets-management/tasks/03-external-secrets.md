# 03 — External Secrets Operator: синк из внешнего источника

## Задача
Поднять `SecretStore` (provider `fake`) и `ExternalSecret`, увидеть синхронизацию в обычный
Secret и проверить, что смена значения в источнике доезжает за `refreshInterval`, а удалённый
вручную Secret оператор пересоздаёт сам.

## Проверка
```bash
kubectl -n lab apply -f manifests/eso/eso-fake.yaml
kubectl -n lab get externalsecret db-from-eso
kubectl -n lab get secret db-from-eso -o jsonpath='{.data.password}' | base64 -d; echo
kubectl -n lab patch secretstore fake-store --type=json \
  -p='[{"op":"replace","path":"/spec/provider/fake/data/1/value","value":"rotated-456"}]'
sleep 20
kubectl -n lab get secret db-from-eso -o jsonpath='{.data.password}' | base64 -d; echo
kubectl -n lab delete secret db-from-eso
sleep 20
kubectl -n lab get secret db-from-eso
```

## Ожидаемый результат
- `ExternalSecret` в статусе `SecretSynced`, `READY True`; пароль `fake-pass-123`.
- После правки источника через ~15 с (`refreshInterval`) пароль стал `rotated-456` —
  без пересоздания объектов.
- Удалённый вручную Secret через один интервал появился снова (владелец — ExternalSecret).
- Вы объяснили, что в git лежит только `ExternalSecret` (ссылка), а значение — во внешнем
  менеджере, и чем provider `fake` отличается от Vault/AWS SM в проде (аутентификация
  оператора в источнике).
