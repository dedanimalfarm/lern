# cluster-kubespray — self-managed Kubernetes через Kubespray на GCE VM

Предпочтительный **production-путь** развёртывания: обычные VM + **Kubespray**
(Ansible), в отличие от managed GKE (`../cluster-gke`). Плюсы: полный контроль,
выбор CNI (здесь **Calico** → реальный NetworkPolicy enforcement), HA-готовность,
а VM можно **stop/start** для экономии (не теряя кластер).

## Что создаётся (Terraform)

- **3 VM** (Ubuntu 22.04, e2-medium): `k8s-cp-1` (control-plane + etcd) +
  `k8s-w-1`/`k8s-w-2` (workers).
- VPC `kubespray-net` + subnet `10.10.0.0/24` + firewall (internal all + внешние
  22/6443).
- CNI **Calico**, Kubernetes **v1.36.1** (проверено 2026-06-02).

## Развернуть с нуля

```bash
# 1) VM
export GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth print-access-token)"
terraform init && terraform apply        # 3 VM + сеть

# 2) inventory для Kubespray (из terraform output)
./gen-inventory.sh > /root/kubespray/inventory/labcluster/hosts.yaml

# 3) ВАЖНО: на свежих Ubuntu-VM отключить unattended-upgrades (держит apt-lock,
#    роняет system_packages по таймауту 300с):
for ip in $(terraform output -json nodes | python3 -c 'import json,sys;[print(v["external"]) for v in json.load(sys.stdin).values()]'); do
  ssh -i /root/.ssh/kubespray ubuntu@$ip 'sudo systemctl stop unattended-upgrades apt-daily.timer apt-daily-upgrade.timer'
done

# 4) Kubespray
cd /root/kubespray   # git clone https://github.com/kubernetes-sigs/kubespray + pip install -r requirements.txt
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory/labcluster/hosts.yaml cluster.yml -b

# 5) kubeconfig на control-машину
ssh -i /root/.ssh/kubespray ubuntu@<CP_EXTERNAL_IP> 'sudo cat /etc/kubernetes/admin.conf' > ~/.kube/kubespray.conf
kubectl --kubeconfig ~/.kube/kubespray.conf config set-cluster cluster.local \
  --server=https://<CP_EXTERNAL_IP>:6443 --insecure-skip-tls-verify=true
kubectl --kubeconfig ~/.kube/kubespray.conf config unset clusters.cluster.local.certificate-authority-data
KUBECONFIG=~/.kube/kubespray.conf kubectl get nodes
```

> `--insecure-skip-tls-verify` нужен потому, что apiserver-сертификат не содержит
> внешний IP. Для «правильного» доступа добавить external IP в
> `supplementary_addresses_in_ssl_keys` (group_vars) и перевыпустить cert.

## Операции (Kubespray)

```bash
cd /root/kubespray
# добавить ноды:    ansible-playbook -i .../hosts.yaml scale.yml -b
# обновить кластер: ansible-playbook -i .../hosts.yaml upgrade-cluster.yml -b
# удалить ноду:     ansible-playbook -i .../hosts.yaml remove-node.yml -b -e node=k8s-w-2
# снести k8s (VM оставить): ansible-playbook -i .../hosts.yaml reset.yml -b
```

## Однокомандный жизненный цикл (рекомендуемый путь)

Ручные шаги выше автоматизированы в `../scripts/cluster/`:

```bash
../scripts/cluster/up.sh [--stacks]  # всё с нуля: VM → Kubespray → kubeconfig → bootstrap (~25 мин)
../scripts/cluster/stop.sh           # остановить VM (платим только за диски)
../scripts/cluster/start.sh          # поднять обратно; сам обновит state/inventory/kubeconfig (IP меняются!)
../scripts/cluster/down.sh           # полный снос (terraform destroy, спросит подтверждение)
```

Кроме того, VM автоматически останавливаются в **22:00 (+04)** — GCE instance
schedule `lab-autostop` (одноразовое создание: `gcloud compute resource-policies
create instance-schedule lab-autostop --region us-central1 --vm-stop-schedule
"0 22 * * *" --timezone Asia/Dubai`; системному агенту Compute нужна роль
`roles/compute.instanceAdmin.v1`). `up.sh` сам привязывает policy к новым VM.

## Экономия и снос (ручной путь)

```bash
# Остановить VM (не платить за CPU; диски остаются; внешние IP МОГУТ смениться):
gcloud compute instances stop k8s-cp-1 k8s-w-1 k8s-w-2 --zone us-central1-a
gcloud compute instances start k8s-cp-1 k8s-w-1 k8s-w-2 --zone us-central1-a
# (после start обновить hosts.yaml/kubeconfig новыми external IP)

# Снести VM полностью:
terraform destroy
```

> Стоимость: 3× e2-medium ≈ $73/мес on-demand пока RUNNING; в `stop` — только
> диски (~$4/мес).
