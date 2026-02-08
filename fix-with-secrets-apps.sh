#!/bin/bash
# Better solution: Create a separate secrets application in ArgoCD
# This keeps everything in GitOps

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

echo "🔧 Better Fix: Separate Secrets Application"
echo ""
echo "This creates a dedicated ArgoCD application for secrets that:"
echo "  - Runs BEFORE other applications (sync-wave -1)"
echo "  - Is managed by ArgoCD with SOPS decryption"
echo "  - Follows GitOps principles"
echo ""

export KUBECONFIG="$SCRIPT_DIR/.demo/kubeconfig"

read -p "Continue? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

# ============================================
# Step 1: Create secrets directory structure
# ============================================

print_step "Step 1: Creating secrets directory..."

mkdir -p .demo/manifests/secrets

# Move secrets to dedicated directory
print_info "Moving secrets to dedicated directory..."

if [ -f .demo/manifests/apps/authentik-dependencies/secrets/postgres-secret.yaml ]; then
    cp .demo/manifests/apps/authentik-dependencies/secrets/postgres-secret.yaml .demo/manifests/secrets/
fi

if [ -f .demo/manifests/apps/authentik-dependencies/secrets/redis-secret.yaml ]; then
    cp .demo/manifests/apps/authentik-dependencies/secrets/redis-secret.yaml .demo/manifests/secrets/
fi

if [ -f .demo/manifests/apps/authentik/secrets/authentik-secret.yaml ]; then
    cp .demo/manifests/apps/authentik/secrets/authentik-secret.yaml .demo/manifests/secrets/
fi

# Create kustomization for secrets
cat > .demo/manifests/secrets/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - postgres-secret.yaml
  - redis-secret.yaml
  - authentik-secret.yaml
EOF

print_info "✅ Secrets directory created"

# ============================================
# Step 2: Create secrets ArgoCD application
# ============================================

print_step "Step 2: Creating secrets application..."

cat > .demo/manifests/cluster-secrets.yaml <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cluster-secrets
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
  annotations:
    argocd.argoproj.io/sync-wave: "-1"  # Apply BEFORE other apps
spec:
  project: default
  source:
    path: .demo/manifests/secrets
    repoURL: https://github.com/KraLeoD/terraform-hcloud-talos  # UPDATE THIS!
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

print_info "✅ Secrets application manifest created"

# ============================================
# Step 3: Update kustomization.yaml
# ============================================

print_step "Step 3: Updating apps kustomization.yaml..."

cat > .demo/manifests/apps/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - nginx
  - traefik.yaml
  - external-dns/application.yaml
  - authentik-dependencies/application.yaml
  - authentik/application.yaml
EOF

print_info "✅ Removed secrets from apps kustomization"

# ============================================
# Step 4: Update app-root to include secrets
# ============================================

print_step "Step 4: Checking app-root.yaml..."

if grep -q "cluster-secrets.yaml" .demo/manifests/app-root.yaml; then
    print_info "app-root.yaml already includes cluster-secrets"
else
    print_warn "You need to manually update app-root.yaml"
    echo ""
    echo "Add this to the path in app-root.yaml:"
    echo "  Instead of: path: .demo/manifests/apps"
    echo "  Keep it as: path: .demo/manifests/apps"
    echo ""
    echo "But we'll deploy cluster-secrets separately!"
fi

# ============================================
# Step 5: Apply to cluster
# ============================================

print_step "Step 5: Applying to cluster..."

# Apply cluster-secrets application
print_info "Deploying cluster-secrets application..."
kubectl apply -f .demo/manifests/cluster-secrets.yaml

sleep 5

# Sync it
print_info "Syncing cluster-secrets..."
kubectl patch application cluster-secrets -n argocd -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}' --type merge 2>/dev/null || print_warn "Already syncing"

sleep 10

# Check secrets
print_info "Checking secrets in cluster..."
kubectl get secrets -n authentik

echo ""

# Delete and recreate app-root
print_info "Refreshing app-root..."
kubectl delete application app-root -n argocd --wait=true 2>/dev/null || print_warn "app-root already deleted"
sleep 5
kubectl apply -f .demo/manifests/app-root.yaml

sleep 10

# Sync all apps
for app in traefik external-dns postgresql redis authentik; do
    print_info "Syncing $app..."
    kubectl patch application $app -n argocd -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}' --type merge 2>/dev/null || print_warn "$app already syncing"
    sleep 3
done

print_info "⏳ Waiting for sync to complete (30s)..."
sleep 30

# ============================================
# Step 6: Check status
# ============================================

print_step "Step 6: Checking status..."
echo ""

kubectl get applications -n argocd

echo ""
print_step "Secrets:"
kubectl get secrets -n authentik

echo ""
print_step "Pods:"
kubectl get pods -n authentik

echo ""
print_info "✅ Setup complete!"
echo ""
print_warn "⚠️  IMPORTANT: Update .demo/manifests/cluster-secrets.yaml with your Git repo URL"
echo ""
print_info "Next steps:"
echo "  1. Update cluster-secrets.yaml with your Git repository URL"
echo "  2. Commit all changes:"
echo "     git add .demo/manifests/"
echo "     git commit -m 'feat: separate secrets application'"
echo "     git push"
echo ""
echo "  3. ArgoCD will manage secrets via GitOps!"
