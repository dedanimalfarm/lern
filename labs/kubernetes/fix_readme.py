import os
import re
import glob

def fix_readme(path, mod_name):
    with open(path, 'r') as f:
        content = f.read()
    
    # KUBECONFIG
    if "export KUBECONFIG=" not in content:
        if "## Предварительные требования" in content:
            content = content.replace("## Предварительные требования\n", "## Предварительные требования\n\n```bash\nexport KUBECONFIG=/root/.kube/kubespray.conf\n```\n")
        elif "## Введение" in content:
            content = content.replace("## Введение\n", "## Предварительные требования\n\n```bash\nexport KUBECONFIG=/root/.kube/kubespray.conf\n```\n\n## Введение\n")
        else:
            content = re.sub(r'(> ⏱ время.*?\n\n)', r'\1## Предварительные требования\n\n```bash\nexport KUBECONFIG=/root/.kube/kubespray.conf\n```\n\n', content)
            
    # Стартовая проверка
    if "Стартовая проверка" not in content and "Предварительная проверка" not in content:
        check_block = "## Стартовая проверка\n\nУбедитесь, что кластер доступен:\n```bash\nkubectl get nodes\n```\n\n"
        if "## Предварительные требования" in content:
            content = re.sub(r'(## Предварительные требования\n.*?\n\n)', r'\1' + check_block, content, flags=re.DOTALL)
        else:
            content = re.sub(r'(> ⏱ время.*?\n\n)', r'\1' + check_block, content)
            
    # Уборка
    if "Уборка" not in content and "Очистка" not in content:
        script_dir = "modules" if "modules/" in path else "projects"
        cleanup_block = f"\n## Уборка\n\nОчистите ресурсы после завершения:\n```bash\n../../scripts/clean/clean-module.sh {script_dir}/{mod_name}\n```\n"
        if "## Практические задания" in content:
            content = content.replace("## Практические задания", cleanup_block + "\n## Практические задания")
        else:
            content += cleanup_block

    # Практические задания (only for projects if missing)
    if "projects/" in path and "Практические задания" not in content and "Задания" not in content:
        content += "\n## Практические задания\n\nПроект сам по себе является большим практическим заданием. Следуйте инструкциям выше.\n"
        
    with open(path, 'w') as f:
        f.write(content)

for f in sorted(glob.glob('modules/*/README.md') + glob.glob('projects/*/README.md')):
    mod_name = os.path.basename(os.path.dirname(f))
    fix_readme(f, mod_name)
