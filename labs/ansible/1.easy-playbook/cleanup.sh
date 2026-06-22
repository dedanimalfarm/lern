#!/bin/bash
set -euo pipefail

echo "Cleaning up lab files..."

# Remove created files
rm -f webservers.yml
rm -f playbooks/files/nginx.conf
rm -f playbooks/templates/index.html.j2
rm -f playbooks/inventory/vagrant.ini

# Attempt to remove directories if they are empty
rmdir playbooks/files 2>/dev/null || true
rmdir playbooks/templates 2>/dev/null || true
rmdir playbooks/inventory 2>/dev/null || true
rmdir playbooks 2>/dev/null || true

echo "✅ Cleanup complete. All student-created files have been removed."
