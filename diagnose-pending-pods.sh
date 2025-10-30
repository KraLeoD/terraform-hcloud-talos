#!/bin/bash
# Diagnose and fix pending pods in authentik namespace

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
MAGENTA='\033[0;35m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
print_section() { 
    echo ""
    echo "=========================================="
    echo -e "${MAGENTA}$1${NC}"
    echo "=========================================="
    echo ""
}

export KUBECONFIG="$SCRIPT_DIR/.demo/kubeconfig"

print_section "🔍 Diagnosing Pending Pods"

# ============================================
# Step 1: Check Pod Status
# ============================================

print_step "Step 1: Current Pod Status"
echo ""
kubectl get pods -n authentik
echo ""

# ============================================
# Step 2: Check Why Pods are Pending
# ============================================

print_step "Step 2: Checking PostgreSQL Pod Events"
echo ""
kubectl describe pod postgresql-0 -n authentik 2>/dev/null | tail -20
echo ""

print_step "Step 3: Checking Redis Pod Events"
echo ""
kubectl describe pod redis-master-0 -n authentik 2>/dev/null | tail -20
echo ""

# ============================================
# Step 4: Check PVCs
# ============================================

print_step "Step 4: Checking PersistentVolumeClaims"
echo ""
kubectl get pvc -n authentik 2>/dev/null || print_warn "No PVCs found"
echo ""

if kubectl get pvc -n authentik &>/dev/null; then
    print_info "PVC Details:"
    kubectl describe pvc -n authentik
    echo ""
fi

# ============================================
# Step 5: Check StorageClass
# ============================================

print_step "Step 5: Checking StorageClass"
echo ""
kubectl get storageclass
echo ""

if ! kubectl get storageclass 2>/dev/null | grep -q "(default)"; then
    print_error "❌ No default StorageClass found!"
    echo ""
    echo "This is the problem! Your cluster doesn't have a storage provisioner."
    echo ""
    print_info "Solutions:"
    echo ""
    echo "Option 1: Install Longhorn (Recommended for production)"
    echo "  kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.5.3/deploy/longhorn.yaml"
    echo ""
    echo "Option 2: Use local-path provisioner (Good for testing)"
    echo "  kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.24/deploy/local-path-storage.yaml"
    echo "  kubectl patch storageclass local-path -p '{\"metadata\": {\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"true\"}}}'"
    echo ""
    echo "Option 3: Disable persistence (Testing only - data will be lost)"
    echo "  Edit .demo/manifests/apps/authentik-dependencies/application.yaml"
    echo "  Set persistence.enabled = false for both PostgreSQL and Redis"
    echo ""
    
    read -p "Install local-path provisioner now? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Installing local-path-provisioner..."
        kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.24/deploy/local-path-storage.yaml
        
        sleep 5
        
        print_info "Setting as default StorageClass..."
        kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
        
        print_info "✅ Storage provisioner installed!"
        echo ""
        print_info "Now restarting pending pods..."
        
        # Delete pending pods to force recreation
        kubectl delete pod postgresql-0 -n authentik --force --grace-period=0 2>/dev/null || true
        kubectl delete pod redis-master-0 -n authentik --force --grace-period=0 2>/dev/null || true
        
        print_info "⏳ Waiting for pods to restart (30s)..."
        sleep 30
        
        echo ""
        print_info "New pod status:"
        kubectl get pods -n authentik
        echo ""
        kubectl get pvc -n authentik
    fi
else
    print_info "✅ Default StorageClass found!"
fi

# ============================================
# Step 6: Check Node Resources
# ============================================

print_step "Step 6: Checking Node Resources"
echo ""
kubectl describe nodes | grep -A 5 "Allocated resources:"
echo ""

# ============================================
# Step 7: Final Recommendations
# ============================================

print_section "Summary and Recommendations"

echo "Common causes of Pending pods:"
echo ""
echo "1. ❌ No StorageClass (most common)"
echo "   → Install local-path-provisioner or Longhorn"
echo ""
echo "2. ❌ Insufficient resources"
echo "   → Check if nodes have enough CPU/memory"
echo ""
echo "3. ❌ Node taints/affinity issues"
echo "   → Check pod tolerations and node selectors"
echo ""

print_info "To monitor pod startup:"
echo "  kubectl get pods -n authentik -w"
echo ""
print_info "To check specific pod events:"
echo "  kubectl describe pod POD_NAME -n authentik"
echo ""
print_info "To check logs once pods start:"
echo "  kubectl logs -n authentik postgresql-0"
echo "  kubectl logs -n authentik redis-master-0"
