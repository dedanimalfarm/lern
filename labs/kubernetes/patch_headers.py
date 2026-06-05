import os
import re

metadata = {
    "01-kubectl-basics": "⏱ время ~15 мин · сложность 1/5 · пререквизиты: базовое знание Linux и Docker",
    "02-pods-lifecycle": "⏱ время ~20 мин · сложность 2/5 · пререквизиты: модуль 01",
    "03-workloads": "⏱ время ~25 мин · сложность 2/5 · пререквизиты: модуль 02",
    "04-networking": "⏱ время ~30 мин · сложность 3/5 · пререквизиты: модуль 03",
    "05-storage": "⏱ время ~25 мин · сложность 2/5 · пререквизиты: модуль 03",
    "06-scheduling": "⏱ время ~20 мин · сложность 2/5 · пререквизиты: модуль 03",
    "07-config-security": "⏱ время ~20 мин · сложность 2/5 · пререквизиты: модуль 03",
    "08-observability": "⏱ время ~20 мин · сложность 2/5 · пререквизиты: Трек 1 (Core)",
    "09-helm-gitops": "⏱ время ~25 мин · сложность 2/5 · пререквизиты: Трек 1 (Core)",
    "10-kubeadm-admin": "⏱ время ~30 мин · сложность 4/5 · пререквизиты: Трек 1 (Core)",
    "11-autoscaling": "⏱ время ~25 мин · сложность 3/5 · пререквизиты: Трек 1 (Core)",
    "12-resource-management": "⏱ время ~20 мин · сложность 3/5 · пререквизиты: Трек 1 (Core)",
    "13-resilience": "⏱ время ~20 мин · сложность 3/5 · пререквизиты: Трек 1 (Core)",
    "14-pod-security-admission": "⏱ время ~25 мин · сложность 3/5 · пререквизиты: Трек 1 и Трек 3",
    "15-network-policy-enforced": "⏱ время ~25 мин · сложность 4/5 · пререквизиты: Трек 1 и Трек 3",
    "16-secrets-management": "⏱ время ~25 мин · сложность 3/5 · пререквизиты: Трек 1 и Трек 3",
    "17-metrics-alerting": "⏱ время ~30 мин · сложность 3/5 · пререквизиты: Трек 1 (Core)",
    "19-crd-operators": "⏱ время ~30 мин · сложность 4/5 · пререквизиты: Трек 1 и Трек 3",
    "20-batch-workflows": "⏱ время ~20 мин · сложность 3/5 · пререквизиты: Трек 1 (Core)",
    "22-ingress-tls": "⏱ время ~30 мин · сложность 4/5 · пререквизиты: Трек 1 (Core)",
    "25-gitops-at-scale": "⏱ время ~30 мин · сложность 4/5 · пререквизиты: Трек 1 (Core)",
    "project-a-platform-namespace": "⏱ время ~20 мин · сложность 2/5 · пререквизиты: Трек 1 (Core)",
    "project-b-stateful-service": "⏱ время ~25 мин · сложность 3/5 · пререквизиты: Трек 1 (Core)",
    "project-c-broken-cluster-lab": "⏱ время ~45 мин · сложность 5/5 · пререквизиты: Трек 1 и Трек 2",
    "project-d-production-readiness": "⏱ время ~30 мин · сложность 4/5 · пререквизиты: Трек 1 и Трек 3",
    "project-e-secure-platform": "⏱ время ~45 мин · сложность 5/5 · пререквизиты: Трек 1, 3 и 4"
}

def process_file(path, mod_name):
    if mod_name not in metadata: return
    with open(path, 'r') as f:
        content = f.read()
    
    header = f"> {metadata[mod_name]}\n\n"
    
    if "⏱ время" in content:
        # Already has header
        return
        
    # Insert right after the title `# ...`
    content = re.sub(r'^(# .*?\n)\n*', r'\1\n' + header, content, count=1)
    
    with open(path, 'w') as f:
        f.write(content)

import glob
for f in glob.glob('modules/*/README.md') + glob.glob('projects/*/README.md'):
    mod_name = os.path.basename(os.path.dirname(f))
    process_file(f, mod_name)
