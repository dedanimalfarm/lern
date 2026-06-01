# cluster-gke — реальный GKE-кластер для прогона лаб

Terraform-описание дешёвого учебного GKE-кластера для прогона лаб из
`../modules`. Нужен **настоящий** кластер, где контейнеры реально запускаются:
`readinessProbe`, `logs`, `exec`, StorageClass, LoadBalancer работают только
на нём.

## Что создаётся

| Ресурс | Значение по умолчанию |
|--------|-----------------------|
| Кластер | `lab-cluster`, **zonal** в `us-central1-a` (один control plane → GKE free tier, ≈$0 за управление) |
| Ноды | **2 × e2-medium** (2 vCPU / 4 GB), on-demand, диск 30 ГБ pd-balanced |
| Сеть | отдельная VPC `lab-cluster-vpc` + subnet с secondary ranges (VPC-native) |
| Проект | `k8s-lab-test-352440` (выделенный, **не** VPN-проект) |

Ориентировочная стоимость: ~**$50/мес пока кластер запущен** (2× e2-medium
on-demand). После теста — `terraform destroy`, останется $0. Для экономии
переключите `use_spot = true` в `terraform.tfvars` (~$6–10/мес, но ноды могут
вытесняться).

## Предпосылки

- `gcloud` авторизован (аккаунт-владелец проекта).
- В проекте включены `container.googleapis.com` и `compute.googleapis.com`.
- `terraform >= 1.5`.

## Применить

Провайдер аутентифицируется коротким токеном из gcloud (ADC-логин не нужен):

```bash
cd labs/kubernetes/cluster-gke

export GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth print-access-token)"   # живёт ~1 час
terraform init
terraform plan
terraform apply -auto-approve
```

> Если `apply` идёт дольше часа и упирается в протухший токен — просто
> повторите `export ...` и `terraform apply` ещё раз (идемпотентно).

## Подключить kubectl

```bash
# плагин аутентификации GKE (нужен kubectl для доступа к GKE)
gcloud components install gke-gcloud-auth-plugin   # или пакетом gke-gcloud-auth-plugin

# вывести готовую команду из outputs и выполнить
terraform output -raw get_credentials_cmd
gcloud container clusters get-credentials lab-cluster --zone us-central1-a --project k8s-lab-test-352440

kubectl get nodes -o wide      # должно показать 2 ноды Ready
```

После этого можно гонять лабы:

```bash
cd ../modules/01-kubectl-basics
kubectl create ns lab --dry-run=client -o yaml | kubectl apply -f -
kubectl -n lab apply -f manifests/app/deploy.yaml -f manifests/app/svc.yaml
bash verify/verify.sh
```

## Снести (чтобы не платить)

```bash
export GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth print-access-token)"
terraform destroy -auto-approve
```

## Создать «такой же» в другом проекте

Поменяйте `project_id` (и при желании `region`/`zone`) в `terraform.tfvars`,
убедитесь, что в том проекте включены те же API и привязан биллинг, и снова
`terraform apply`. Всё остальное (VPC, кластер, пул) поднимется идентично.
