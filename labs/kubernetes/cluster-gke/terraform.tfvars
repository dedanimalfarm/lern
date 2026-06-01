# Конкретные значения этого стенда. Project ID — выделенный учебный проект
# (НЕ VPN-проект). Чтобы поднять «такой же» в другом проекте — поменяйте
# project_id и примените заново.
project_id        = "k8s-lab-test-352440"
region            = "us-central1"
zone              = "us-central1-a"
cluster_name      = "lab-cluster"
node_machine_type = "e2-medium"
node_count        = 2
use_spot          = false
disk_size_gb      = 30
