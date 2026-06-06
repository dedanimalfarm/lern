#!/usr/bin/env bash
set -euo pipefail

kubectl delete namespace lab-gateway --ignore-not-found=true
