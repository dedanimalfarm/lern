import re
import glob

replacements = {
    'modules/10-kubeadm-admin/verify/verify.sh': (r'ok "module 10 baseline checks passed"', 'ok "module 10 verified"'),
    'projects/project-a-platform-namespace/verify/verify.sh': (r'ok "project A verified"', 'ok "project-a verified"'),
    'projects/project-b-stateful-service/verify/verify.sh': (r'ok "project B verified"', 'ok "project-b verified"'),
    'projects/project-c-broken-cluster-lab/verify/verify.sh': (r'ok "project C verify script executed"', 'ok "project-c verified"'),
    'projects/project-e-secure-platform/verify/verify.sh': (r'ok "project-e secure-platform verified"', 'ok "project-e verified"')
}

for path, (old, new) in replacements.items():
    with open(path, 'r') as f:
        content = f.read()
    content = re.sub(old, new, content)
    with open(path, 'w') as f:
        f.write(content)

