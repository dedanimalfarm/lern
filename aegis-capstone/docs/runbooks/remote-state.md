---
title: Runbook — удалённый Terraform state в Azure Blob
status: stable
audience: [ops, contributors, llm]
last_verified: 2026-05-15
related:
  - ../../terraform/versions.tf
  - deploy.md
  - redeploy-2026-05-09.md
---

# Runbook: удалённый state в Azure Blob

> Контекст: до 2026-05-15 `terraform.tfstate` хранился локально в `terraform/terraform.tfstate`. Это делало совместную работу опасной (нет блокировок → гонка двух `apply`) и хрупкой (потеря ноута = потеря стейта). 2026-05-15 стейт мигрирован в Azure Blob Storage с AD-аутентификацией, lease-lock'ом и версионированием.

## TL;DR

- State лежит в Azure Blob: `aegistfstate52018f/tfstate/aegis-v4.tfstate` (RG `aegis-tfstate-rg`, регион `westeurope`).
- Auth — Azure AD, **не** access-keys. Нужна роль `Storage Blob Data Contributor` на storage account.
- На свежей машине: `az login` → `export ARM_USE_AZUREAD=true` → `terraform init` → готово.
- Локальный `terraform.tfstate` больше **не должен** содержать данных. Если он непустой — что-то сломалось.

## Координаты бэкенда (SSOT)

Источник правды — блок `backend "azurerm"` в [`terraform/versions.tf`](../../terraform/versions.tf). Дублирую сюда для удобства:

| Параметр | Значение |
|---|---|
| Resource Group | `aegis-tfstate-rg` |
| Регион | `westeurope` |
| Storage Account | `aegistfstate52018f` |
| Контейнер | `tfstate` |
| Blob (key) | `aegis-v4.tfstate` |
| Auth | `use_azuread_auth = true` (через `az login`, RBAC) |
| SKU | `Standard_LRS`, `StorageV2`, TLS 1.2, public blob OFF, HTTPS-only |
| Versioning | **ON** (Blob versioning) |
| Soft delete | OFF (см. раздел «Расширения») |

Почему отдельная RG, не одна из `aegis-v4-az-r{1,2,3}`: те RG регулярно сносятся при teardown (`terraform destroy` + `az group delete`). Стейт должен переживать teardown.

Почему `westeurope`, а не один из регионов проекта: низкая задержка от оператора (`5.77.205.144/32`), стабильный регион вне ротации `southeastasia/australia*`, не зависит от Packer-RG в r3.

Почему `Standard_LRS`: 150 KB стейта — копейки даже на GRS, но LRS даёт более простую модель консистентности и без cross-region latency на запись. Для capstone-нагрузки достаточно.

## Onboarding соавтора (со свежим клоном)

```bash
# 1) Подтянуть backend-блок
git pull

# 2) Залогиниться в Azure под своей учёткой
az login
az account set --subscription c619a462-257e-4527-a932-0e02331e2341
az account show          # проверка

# 3) Попросить владельца подписки (tana1957tana@via17.com) выдать роль
#    Storage Blob Data Contributor на SA. Без неё будет 403.
#    Команда, которую выполняет владелец, подставив твой UPN или OID:
#
#      az role assignment create \
#        --assignee <UPN_or_OID> \
#        --role "Storage Blob Data Contributor" \
#        --scope "/subscriptions/c619a462-257e-4527-a932-0e02331e2341/resourceGroups/aegis-tfstate-rg/providers/Microsoft.Storage/storageAccounts/aegistfstate52018f"

# 4) Удалить (если остался) пустой локальный стейт-файл
cd terraform
rm -f terraform.tfstate terraform.tfstate.backup terraform.tfstate.*.backup

# 5) Поднять backend — Terraform подтянет стейт из Azure
export ARM_USE_AZUREAD=true     # удобно прописать в ~/.bashrc
terraform init

# 6) Sanity-check — должен быть "No changes":
terraform plan
```

Признаки, что всё прошло хорошо:

- `terraform init` пишет `Successfully configured the backend "azurerm"!`.
- `terraform plan` в начале и в конце пишет `Acquiring state lock` / `Releasing state lock` (это и есть lease-lock).
- `terraform state list` показывает ~60 ресурсов (5 VM, 10 дисков, 3 VNet, peerings, NICs, attachments, local_file'ы).
- В `.terraform/terraform.tfstate` (это **конфиг backend'а**, не сам стейт) поле `backend.config.access_key` равно `null` — значит AD-auth работает, ключи нигде не валяются.

## Работа в обычном режиме (чек-лист при изменении `.tf`)

Никаких флагов больше не нужно после первичной настройки — `ARM_USE_AZUREAD=true` в окружении и `az login`. Дальше — стандартный пятишаговый цикл:

```bash
export ARM_USE_AZUREAD=true                  # один раз на сессию (или в ~/.bashrc)
cd /root/lern/aegis-capstone/terraform

# 1. Отредактировал foo.tf — форматирование
terraform fmt

# 2. Синтаксическая валидация (offline, Azure не дёргается)
terraform validate

# 3. Plan: читает state из Blob, рефрешит, считает diff
terraform plan -out=tfplan

# 4. Apply ровно того, что показал plan
terraform apply tfplan

# 5. Артефакт плана содержит чувствительные значения — удалить
rm -f tfplan
```

### Что происходит со стейтом на каждом шаге

| Шаг | Lock | Чтение Blob | Запись Blob | Замечание |
|---|---|---|---|---|
| `terraform fmt` / `validate` | — | — | — | Чисто локальные, можно гонять как угодно часто |
| `terraform plan` | read-lock | да | да (refresh) | Refresh обновляет стейт под реальность и пишет обратно |
| `terraform plan -out=tfplan` | read-lock | да | да | То же + кладёт diff в локальный файл |
| `terraform apply tfplan` | **write-lock** | да | да (после каждого ресурса) | Параллельный `apply` будет ждать |
| `terraform apply` (без файла) | **write-lock** | да | да | То же + интерактивное `yes` |

### Полезные команды без изменения инфры

```bash
terraform state list                                      # что в стейте
terraform state show 'azurerm_linux_virtual_machine.vms["app"]'   # детали ресурса
terraform apply -refresh-only                             # синхронизировать стейт с реальностью без diff'а
terraform output                                          # выводы (IP, hostname'ы)
```

### Чек-лист «всё ок» после работы

- [ ] `terraform plan` чистый — пишет `No changes. Your infrastructure matches the configuration.`
- [ ] `git status` не показывает изменений в `terraform.tfstate*` — они должны быть пустыми/отсутствовать. Если внезапно появился непустой — **не коммитить**, что-то сломалось.
- [ ] `git status` показывает только `.tf` / `.md` / `host_vars/*.yml` / `hosts.ini` / `ssh_config` — последние четыре генерятся `inventory.tf`, это нормально.
- [ ] В Azure Blob появилась новая версия `aegis-v4.tfstate` с актуальным временем (`az storage blob list ... --include v`).
- [ ] Если меняли `azure.tf` или `inventory.tf` — пробежать `ansible-playbook --check` чтобы убедиться, что Ansible видит новый inventory.

### Если `plan`/`apply` ругается на lock

```
Error: Error acquiring the state lock
  Lock Info:
    ID:        7a3c...
    Operation: OperationTypeApply
    Who:       tatiana@host
    Created:   2026-05-15T16:42:11Z
```

Это **нормальная защита**, не баг — кто-то реально работает. Действия по убыванию вежливости:

1. Подождать — `apply` обычно заканчивается за минуты, lock снимется автоматически.
2. Списаться с тем, кто в поле `Who:` — выяснить, реально ли он работает.
3. **Только** убедившись, что процесс мёртв — `terraform force-unlock <ID>` (см. раздел ниже).

## Откат к предыдущей версии стейта (Blob versioning)

Versioning включён, поэтому каждая запись стейта сохраняется как отдельная версия. Если случайно затёрли — восстанавливается так:

```bash
# 1) Список версий
az storage blob list \
  --account-name aegistfstate52018f \
  --container-name tfstate \
  --auth-mode login \
  --include v \
  --query "[?name=='aegis-v4.tfstate'].{ver:versionId, size:properties.contentLength, modified:properties.lastModified}" \
  -o table

# 2) Скопировать выбранную версию поверх текущей
az storage blob copy start \
  --account-name aegistfstate52018f \
  --auth-mode login \
  --destination-container tfstate \
  --destination-blob aegis-v4.tfstate \
  --source-uri "https://aegistfstate52018f.blob.core.windows.net/tfstate/aegis-v4.tfstate?versionId=2026-05-15T15:38:17.0878702Z"
```

После копирования следующий `terraform plan` увидит восстановленный стейт.

## Force-unlock (аварийный)

Если процесс упал и lease на блобе остался висеть (увидишь `Error acquiring the state lock`, при этом никто реально не работает):

```bash
# 1) Узнать lock ID из текста ошибки (UUID после "ID:")
# 2) Снять lock
terraform force-unlock <lock-id>
```

Это **разрушительная** операция — если другой агент действительно работает, ты можешь повредить стейт. Перед запуском убедись, что параллельных `apply` нет.

## Удаление локальных стейт-файлов

В `terraform/.gitignore` уже есть `*.tfstate` и `*.backup`, но локально они могут оставаться после миграции. Их можно удалять без последствий — single source of truth теперь блоб:

```bash
rm -f terraform/terraform.tfstate \
      terraform/terraform.tfstate.backup \
      terraform/terraform.tfstate.*.backup
```

## Расширения (опционально)

### Soft-delete контейнера/блобов

Versioning защищает от случайной перезаписи, но **не** от удаления блоба или контейнера целиком. Soft-delete добавляет окно восстановления:

```bash
az storage account blob-service-properties update \
  --account-name aegistfstate52018f \
  --resource-group aegis-tfstate-rg \
  --enable-delete-retention true \
  --delete-retention-days 30 \
  --enable-container-delete-retention true \
  --container-delete-retention-days 30
```

Стоимость пренебрежимо мала (несколько мегабайт хранения максимум).

### Geo-redundant storage (GRS)

Если когда-то понадобится защита от регионального outage Azure — можно переключить SKU на `Standard_GRS`. Это удваивает стоимость хранения (всё равно копейки) и даёт асинхронную репликацию в парный регион (`northeurope` для `westeurope`).

```bash
az storage account update \
  --name aegistfstate52018f \
  --resource-group aegis-tfstate-rg \
  --sku Standard_GRS
```

### Отдельный SP / Managed Identity для CI

Сейчас `az login` идёт под человеческой учёткой. Для автоматизации (CI/Azure DevOps Pipelines из [EP-001..003](../epics/)) нужен Service Principal или Managed Identity с тем же RBAC `Storage Blob Data Contributor` на SA. Auth-режим в backend'е менять не нужно — `use_azuread_auth = true` работает и для SP/MI.

## Подводные камни

- **403 при `terraform init`** — RBAC ещё не применился (Azure пропагирует роли до ~60 секунд), либо неверная подписка в `az account show`. Подожди минуту и повтори.
- **`Error: building account: unable to configure ResourceManagerAccount: ...`** — нет `az login` или истёк токен. `az login` снова.
- **Непустой `terraform.tfstate` после миграции** — что-то пошло не так, **не коммитить**. Проверь, что `init -migrate-state` отработал без ошибок.
- **`ARM_USE_AZUREAD` не выставлен** — Terraform попытается взять access-key из SA. Без RBAC на data-plane это даст 403, с RBAC на control-plane (`Storage Account Contributor`) — может неожиданно сработать через listKeys и обойти AD-аудит. Лучше всегда экспортировать переменную.
- **Удаление SA или RG руками** — потеряешь стейт **навсегда** (если soft-delete выключен). Имя `aegistfstate52018f` лучше пометить замком в Azure Portal: `az lock create --lock-type CanNotDelete --name protect-tfstate --resource-group aegis-tfstate-rg`.

## История

| Дата | Что | Кто |
|---|---|---|
| 2026-05-15 | Миграция local → Azure Blob, RG `aegis-tfstate-rg`, SA `aegistfstate52018f`, versioning ON | tana1957tana@via17.com |
