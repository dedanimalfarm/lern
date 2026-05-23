# 00 · Подготовка стенда

## Цель

Получить **одну Ubuntu 22.04/24.04 VM** с sudo-доступом по SSH-ключу и контрольную (локальную) машину с установленным Ansible. Один и тот же стенд переиспользуется во всех лабах сборника. Курс автор написан и проверен на 24.04 (EC2 `t3.micro`).

## Что-такого на 24.04 vs 22.04 (важно)

- DNS-резолвер — `systemd-resolved` (как и на 22.04), но `resolv.conf` теперь сразу симлинк на `/run/systemd/resolve/stub-resolv.conf`.
- ufw жив и работает поверх `nftables` (на 22.04 был выбор iptables-legacy/nf). Все команды лабы переносимы.
- В образе AWS Ubuntu **уже нет** Python 2; `python3` всегда есть — Ansible счастлив.
- `netplan` тот же, бэкенд — `systemd-networkd` (на десктопах — `NetworkManager`).
- Если ставишь HashiCorp Vault или Grafana — у обоих репозиториев есть `noble` (24.04) и `jammy` (22.04). Дистро-кодовое имя бери из `lsb_release -cs`.

## Варианты стенда (выбери один)

> **SSH-ключ.** В этом курсе используем уже существующий ключ `~/.ssh/vast`
> (`~/.ssh/vast.pub` = `ssh-ed25519 …vast.ai-dedanimalfarm`). Если у тебя его нет —
> сгенерируй любой `ssh-keygen -t ed25519 -f ~/.ssh/lab` и подставляй своё имя
> везде ниже.

### Вариант 1 — Multipass (Linux/macOS/Windows, быстрее всего)

```bash
multipass launch 22.04 --name junior-lab --cpus 2 --memory 2G --disk 10G
multipass exec junior-lab -- bash -c 'sudo apt-get update && sudo apt-get install -y python3'
multipass info junior-lab          # запомни IPv4
multipass exec junior-lab -- sudo bash -c \
  'echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/99-ubuntu'
```

Прокидываем наш существующий ключ:

```bash
multipass transfer ~/.ssh/vast.pub junior-lab:/tmp/k.pub
multipass exec junior-lab -- bash -c 'mkdir -p ~/.ssh && cat /tmp/k.pub >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
```

### Вариант 2 — KVM/libvirt (если есть гипервизор)

```bash
virt-install --name junior-lab --ram 2048 --vcpus 2 --disk size=10 \
  --os-variant ubuntu22.04 --network bridge=br0 \
  --location 'http://archive.ubuntu.com/ubuntu/dists/jammy/main/installer-amd64/' \
  --extra-args 'console=ttyS0' --graphics none
```

### Вариант 3 — облако (AWS t3.micro / Azure B1s) ← референс-стенд курса

Бери официальный Ubuntu 22.04 или 24.04 LTS AMI/image, открой `22/tcp` своему IP, остальное — внутри стенда. На EC2 пользователь — `ubuntu`, на Azure-image — `azureuser`. NOPASSWD-sudo уже в комплекте у обоих образов.

На AWS:

```bash
# с контрольной машины
aws ec2 describe-instances --instance-ids <ID> \
  --query 'Reservations[].Instances[].[PublicIpAddress,State.Name]' --output text
ssh -i ~/.ssh/vast ubuntu@<PUBLIC-IP>
```

> Помни: после `stop/start` инстанса публичный IP меняется (если не EIP).

### Вариант 4 — Vagrant (на крайний случай)

```ruby
# Vagrantfile
Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/jammy64"
  config.vm.hostname = "junior-lab"
  config.vm.network "private_network", ip: "192.168.56.10"
  config.vm.provider "virtualbox" do |vb|
    vb.cpus = 2
    vb.memory = 2048
  end
end
```

## На контрольной машине

```bash
sudo apt-get update
sudo apt-get install -y ansible-core git curl jq
ansible --version          # ожидаем ≥ 2.14
```

Создай рабочий каталог:

```bash
mkdir -p ~/work/junior-lab && cd ~/work/junior-lab
git init && git commit --allow-empty -m "chore: init lab repo"
```

## Чек: всё ли работает

```bash
# 1. SSH без пароля
ssh -i ~/.ssh/vast ubuntu@<VM-IP> 'hostname; id; sudo -n true && echo SUDO_OK'

# 2. Ansible видит хост
cat > inventory.ini <<'EOF'
[lab]
junior-lab ansible_host=<VM-IP> ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/vast
EOF

ansible -i inventory.ini lab -m ping
# ожидаемый ответ: "ping": "pong"
```

Если оба шага зелёные — стенд готов. Переходи к [`../01-ansible-baseline/`](../01-ansible-baseline/).

## Типовые грабли

| Симптом | Причина | Лечение |
|---------|---------|---------|
| `Permission denied (publickey)` | ключ не доехал в `authorized_keys` | проверь права 0600, владельца `ubuntu:ubuntu` |
| `sudo: a password is required` | нет NOPASSWD-правила | `echo "ubuntu ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/99-ubuntu` |
| `/usr/bin/python3: not found` | минимальный образ | `apt-get install -y python3` на VM |
| Multipass не видит хост по имени | DNS Multipass | используй IP из `multipass info` |
