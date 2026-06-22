#!/bin/bash
set -euo pipefail

echo "Running verification for Ansible Lab 1..."

MISSING_FILES=0

check_file_exists() {
    if [[ ! -f "$1" ]]; then
        echo "❌ Missing file: $1"
        MISSING_FILES=$((MISSING_FILES + 1))
    else
        echo "✅ Found: $1"
    fi
}

echo "1. Checking required files..."
check_file_exists "webservers.yml"
check_file_exists "playbooks/files/nginx.conf"
check_file_exists "playbooks/templates/index.html.j2"
check_file_exists "playbooks/inventory/vagrant.ini"

if [[ $MISSING_FILES -gt 0 ]]; then
    echo "❌ Verification failed: Some files are missing. Please create them as instructed in the README."
    exit 1
fi

echo "2. Checking YAML syntax of the playbook..."
if command -v ansible-playbook >/dev/null 2>&1; then
    if ansible-playbook --syntax-check -i playbooks/inventory/vagrant.ini webservers.yml >/dev/null; then
        echo "✅ Playbook syntax is valid."
    else
        echo "❌ Playbook syntax check failed."
        ansible-playbook --syntax-check -i playbooks/inventory/vagrant.ini webservers.yml
        exit 1
    fi
else
    echo "⚠️ ansible-playbook command not found. Skipping syntax check."
fi

echo "✅ All local verification checks passed!"
echo "If you have run the playbook, don't forget to check http://localhost:8080 in your browser."
exit 0
