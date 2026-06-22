#!/usr/bin/env bash
set -euo pipefail

echo "Cleaning up Resource Management lab..."

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

kubectl delete -k "$DIR/../manifests/" --ignore-not-found -n lab 2>/dev/null || true
kubectl delete deploy lab-low-app -n lab --ignore-not-found 2>/dev/null || true
kubectl delete pod lab-high-pod mem-hog -n lab --ignore-not-found --force 2>/dev/null || true
kubectl delete priorityclass lab-low lab-high --ignore-not-found 2>/dev/null || true

# Remove lab-prio label from any nodes
for n in $(kubectl get nodes -l lab-prio=target -o name 2>/dev/null || true); do 
  kubectl label "$n" lab-prio- 2>/dev/null || true
done

echo "Cleanup complete."
