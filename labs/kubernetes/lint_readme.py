import os
import glob

def check_readme(path):
    with open(path, 'r') as f:
        content = f.read()
    
    missing = []
    if "export KUBECONFIG=" not in content:
        missing.append("KUBECONFIG")
    if "Стартовая проверка" not in content and "Предварительная проверка" not in content:
        missing.append("Стартовая проверка")
    if "Уборка" not in content and "Очистка" not in content:
        missing.append("Уборка")
    if "Практические задания" not in content and "Задания" not in content:
        missing.append("Практические задания")
        
    return missing

for f in sorted(glob.glob('modules/*/README.md') + glob.glob('projects/*/README.md')):
    mod_name = os.path.basename(os.path.dirname(f))
    missing = check_readme(f)
    if missing:
        print(f"{mod_name}: missing {', '.join(missing)}")
