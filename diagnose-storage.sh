#!/bin/bash
# Diagnose storage and pod startup issues

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

echo "🔍 Storage and Pod Diagnostics"
echo "=============================="
echo ""

# Step 1: Check storage provisioner
print_step "Step 1: Local Path Provisioner Status"
kubectl get pods -n local-path-storage
echo ""

# Step 2: Check PVCs
print_step "Step 2: PersistentVolumeClaim Status"
kubectl get pvc -n authentik
echo ""

# Step 3: Describe PVCs to see events
print_step "Step 3: PostgreSQL PVC Details"
kubectl describe pvc data-postgresql-0 -n authentik | tail -20
echo ""

print_step "Step 4: Redis PVC Details"
kubectl describe pvc redis-data-redis-master-0 -n authentik | tail -20
echo ""

# Step 5: Check pod status
print_step "Step 5: Pod Status in authentik namespace"
kubectl get pods -n authentik
echo ""

# Step 6: Describe pods to see why they're pending
print_step "Step 6: PostgreSQL Pod Events"
kubectl describe pod postgresql-0 -n authentik | tail -30
echo ""

print_step "Step 7: Redis Pod Events"
kubectl describe pod redis-master-0 -n authentik | tail -30
echo ""

# Step 8: Check node resources
print_step "Step 8: Node Status"
kubectl get nodes -o wide
echo ""

# Step 9: Check node taints
print_step "Step 9: Node Taints"
kubectl get nodes -o json | jq -r '.items[] | .metadata.name + ": " + (.spec.taints // [] | tostring)'
echo ""

# Step 10: Check if nodes have required storage path
print_step "Step 10: Check Storage Path on Nodes"
print_info "Checking if /var/lib/rancher/local-path-provisioner exists on nodes..."
for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
    echo "Node: $node"
    kubectl debug node/$node -it --image=alpine -- sh -c "ls -la /host/var/lib/rancher/ 2>/dev/null || echo 'Directory not accessible'" 2>/dev/null || echo "  Could not check"
done
echo ""

# Step 11: Check local-path-provisioner logs
print_step "Step 11: Local Path Provisioner Logs (last 20 lines)"
kubectl logs -n local-path-storage -l app=local-path-provisioner --tail=20
echo ""

print_info "=============================="
print_info "Diagnosis Complete"
print_info "=============================="
echo ""
print_info "Common Issues:"
echo "  1. Pods pending due to taints - check node taints above"
echo "  2. Storage path doesn't exist - check Step 10"
echo "  3. Provisioner doesn't have permissions - check logs in Step 11"
echo ""
