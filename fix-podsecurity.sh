#!/bin/bash
# Fix PodSecurity issue for local-path-provisioner

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

echo "🔧 Fixing PodSecurity for Local Path Provisioner"
echo "================================================"
echo ""

print_info "The issue: Kubernetes PodSecurity is blocking hostPath volumes"
print_info "The fix: Label the namespace to allow privileged operations"
echo ""

# Step 1: Label the namespace
print_step "Step 1: Adding PodSecurity labels to local-path-storage namespace"
echo ""

kubectl label namespace local-path-storage \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/audit=privileged \
  pod-security.kubernetes.io/warn=privileged \
  --overwrite

print_info "✅ Namespace labeled"
echo ""

# Step 2: Delete failed helper pods
print_step "Step 2: Cleaning up failed helper pods"
echo ""

kubectl delete pods -n local-path-storage -l app=local-path-provisioner-helper --force --grace-period=0 2>/dev/null || print_info "No helper pods to clean"

print_info "✅ Cleanup done"
echo ""

# Step 3: Delete pending PVCs to trigger recreation
print_step "Step 3: Deleting pending PVCs to trigger recreation"
echo ""

kubectl delete pvc data-postgresql-0 redis-data-redis-master-0 -n authentik --wait=false 2>/dev/null || print_info "PVCs already deleted"

print_info "✅ PVCs deleted"
echo ""

# Step 4: Restart the local-path-provisioner
print_step "Step 4: Restarting local-path-provisioner"
echo ""

kubectl rollout restart deployment local-path-provisioner -n local-path-storage

print_info "⏳ Waiting for provisioner to restart..."
kubectl rollout status deployment local-path-provisioner -n local-path-storage --timeout=60s

print_info "✅ Provisioner restarted"
echo ""

# Step 5: Delete and recreate the statefulsets
print_step "Step 5: Recreating PostgreSQL and Redis"
echo ""

kubectl delete statefulset postgresql redis-master -n authentik --ignore-not-found=true --wait=false 2>/dev/null || print_info "StatefulSets already deleted"

print_info "⏳ Waiting 15 seconds for recreation..."
sleep 15

echo ""
print_info "Current status:"
echo ""

echo "Provisioner:"
kubectl get pods -n local-path-storage
echo ""

echo "PVCs:"
kubectl get pvc -n authentik
echo ""

echo "Pods:"
kubectl get pods -n authentik
echo ""

print_info "================================================"
print_info "Fix Applied!"
print_info "================================================"
echo ""

print_info "Monitor progress with:"
echo "  kubectl get pods -n authentik -w"
echo ""
print_info "Check PVC binding:"
echo "  kubectl get pvc -n authentik"
echo ""
print_info "Check volumes:"
echo "  kubectl get pv"
echo ""

print_warn "It may take 1-2 minutes for PVCs to bind and pods to start"
