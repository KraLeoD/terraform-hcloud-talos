#!/bin/bash
# Quick fix for Authentik storage issues

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

echo "🔧 Fixing Authentik Storage Issues"
echo "===================================="
echo ""

# Step 1: Delete stuck resources
print_step "Step 1: Removing stuck resources in authentik namespace"
print_info "This will force recreation with new configuration..."
echo ""

# Delete statefulsets (will be recreated by Helm)
kubectl delete statefulset postgresql redis-master -n authentik --ignore-not-found=true --wait=false 2>/dev/null || true

# Delete PVCs (will be recreated)
kubectl delete pvc data-postgresql-0 redis-data-redis-master-0 -n authentik --ignore-not-found=true --wait=false 2>/dev/null || true

print_info "✅ Cleanup initiated"
echo ""

# Wait a moment for cleanup
print_info "Waiting 10 seconds for cleanup..."
sleep 10

# Step 2: Trigger ArgoCD sync
print_step "Step 2: Triggering ArgoCD sync"
echo ""

# Refresh apps to pick up new manifests
print_info "Refreshing applications..."
kubectl patch application postgresql -n argocd -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}' --type merge 2>/dev/null || true
kubectl patch application redis -n argocd -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}' --type merge 2>/dev/null || true
kubectl patch application authentik -n argocd -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}' --type merge 2>/dev/null || true

print_info "✅ Sync triggered"
echo ""

# Step 3: Watch the progress
print_step "Step 3: Monitoring deployment progress"
echo ""
print_info "Waiting 20 seconds for resources to be created..."
sleep 20

echo ""
print_info "Current status:"
echo ""

echo "Storage:"
kubectl get storageclass
echo ""

echo "PVCs:"
kubectl get pvc -n authentik
echo ""

echo "Pods:"
kubectl get pods -n authentik
echo ""

print_info "=============================="
print_info "Initial deployment started"
print_info "=============================="
echo ""

print_info "Monitor with:"
echo "  kubectl get pods -n authentik -w"
echo ""
print_info "Check PVC status:"
echo "  kubectl get pvc -n authentik"
echo ""
print_info "View pod events:"
echo "  kubectl describe pod postgresql-0 -n authentik"
echo "  kubectl describe pod redis-master-0 -n authentik"
echo ""

print_warn "If pods are still pending after 2 minutes, run:"
echo "  kubectl describe pvc -n authentik"
echo "  kubectl logs -n local-path-storage -l app=local-path-provisioner"
