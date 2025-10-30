#!/bin/bash
# Continue deployment from current state
# Use this to complete the deployment after cluster is ready

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_section "🔄 Continue Deployment"

echo "This script will:"
echo "  1. Wait for cluster to be ready"
echo "  2. Create necessary namespaces"
echo "  3. Install ArgoCD"
echo "  4. Configure SOPS plugin"
echo "  5. Deploy app-root"
echo ""

read -p "Continue? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

# Set kubeconfig
export KUBECONFIG="$SCRIPT_DIR/.demo/kubeconfig"
export TALOSCONFIG="$SCRIPT_DIR/.demo/talosconfig"

if [ ! -f "$KUBECONFIG" ]; then
    print_error "Kubeconfig not found. Run deploy-everything.sh first"
    exit 1
fi

# Get credentials
if [[ -z "${CLOUDFLARE_API_TOKEN}" ]]; then
    read -s -p "Enter your Cloudflare API Token: " CLOUDFLARE_API_TOKEN
    echo ""
    export CLOUDFLARE_API_TOKEN
fi

# Get cluster IP
cd .demo
CLUSTER_IP=$(terraform output -raw cluster_endpoint)
cd ..

# ============================================
# Wait for Cluster
# ============================================

print_section "Waiting for Cluster to be Ready"

./wait-for-cluster.sh

# ============================================
# Create Namespaces & Secrets
# ============================================

print_section "Creating Namespaces and Secrets"

print_step "Creating namespaces..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace external-dns --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace authentik --dry-run=client -o yaml | kubectl apply -f -

print_info "✅ Namespaces created"

if [ -f .sops/age.agekey ]; then
    print_step "Storing SOPS age key in cluster..."
    kubectl create secret generic sops-age \
        --from-file=age.agekey=.sops/age.agekey \
        -n argocd \
        --dry-run=client -o yaml | kubectl apply -f -
    print_info "✅ SOPS age key stored"
else
    print_warn "⚠️  No age key found at .sops/age.agekey"
fi

if [ -n "$CLOUDFLARE_API_TOKEN" ]; then
    print_step "Storing Cloudflare credentials..."
    kubectl create secret generic cloudflare-api-token \
        --from-literal=apiToken="$CLOUDFLARE_API_TOKEN" \
        -n external-dns \
        --dry-run=client -o yaml | kubectl apply -f -
    print_info "✅ Cloudflare credentials stored"
fi

# ============================================
# Install ArgoCD
# ============================================

print_section "Installing ArgoCD"

if kubectl get namespace argocd &>/dev/null && kubectl get deployment argocd-server -n argocd &>/dev/null; then
    print_info "ArgoCD already installed, skipping..."
else
    print_step "Installing ArgoCD..."
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.11.4/manifests/install.yaml
    
    print_info "⏳ Waiting for ArgoCD to be ready..."
    sleep 30
    
    kubectl wait --for=condition=available --timeout=300s \
        deployment/argocd-server \
        deployment/argocd-repo-server \
        -n argocd
    
    print_info "✅ ArgoCD installed"
fi

# ============================================
# Configure SOPS Plugin
# ============================================

print_section "Configuring SOPS Plugin"

print_step "Installing SOPS plugin for ArgoCD..."

# Check if already configured
if kubectl get deployment argocd-repo-server -n argocd -o yaml | grep -q "install-sops"; then
    print_info "SOPS plugin already configured"
else
    # Add init container
    kubectl patch deployment argocd-repo-server -n argocd --type='json' -p='[
      {
        "op": "add",
        "path": "/spec/template/spec/initContainers",
        "value": [
          {
            "name": "install-sops",
            "image": "alpine:3.18",
            "command": [
              "sh", "-c",
              "apk add --no-cache curl && cd /custom-tools && curl -Lo sops https://github.com/getsops/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64 && chmod +x sops && curl -Lo age.tar.gz https://github.com/FiloSottile/age/releases/download/v1.1.1/age-v1.1.1-linux-amd64.tar.gz && tar xzf age.tar.gz && mv age/age age/age-keygen . && rm -rf age age.tar.gz && chmod +x age age-keygen"
            ],
            "volumeMounts": [{"mountPath": "/custom-tools", "name": "custom-tools"}]
          }
        ]
      }
    ]'
    
    # Add volumes
    kubectl patch deployment argocd-repo-server -n argocd --type='json' -p='[
      {"op": "add", "path": "/spec/template/spec/volumes/-", "value": {"name": "custom-tools", "emptyDir": {}}},
      {"op": "add", "path": "/spec/template/spec/volumes/-", "value": {"name": "sops-age", "secret": {"secretName": "sops-age"}}}
    ]'
    
    # Add volume mounts
    kubectl patch deployment argocd-repo-server -n argocd --type='json' -p='[
      {"op": "add", "path": "/spec/template/spec/containers/0/volumeMounts/-", "value": {"mountPath": "/custom-tools", "name": "custom-tools"}},
      {"op": "add", "path": "/spec/template/spec/containers/0/volumeMounts/-", "value": {"name": "sops-age", "mountPath": "/sops", "readOnly": true}}
    ]'
    
    # Add environment variables
    kubectl patch deployment argocd-repo-server -n argocd --type='json' -p='[
      {"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name": "SOPS_AGE_KEY_FILE", "value": "/sops/age.agekey"}},
      {"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name": "PATH", "value": "/custom-tools:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"}}
    ]'
    
    print_info "⏳ Waiting for ArgoCD repo-server to restart..."
    kubectl rollout status deployment/argocd-repo-server -n argocd --timeout=300s
    
    print_info "✅ SOPS plugin configured"
fi

# ============================================
# Deploy App-Root
# ============================================

print_section "Deploying GitOps Bootstrap"

if kubectl get application app-root -n argocd &>/dev/null; then
    print_info "app-root already deployed"
else
    print_warn "⚠️  Make sure .demo/manifests/app-root.yaml has your Git repository URL!"
    read -p "Deploy app-root now? (y/n) " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kubectl apply -f .demo/manifests/app-root.yaml
        print_info "✅ App-root deployed"
    else
        print_warn "Skipped app-root deployment"
    fi
fi

# ============================================
# Show Access Info
# ============================================

print_section "Access Information"

ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d) || ARGOCD_PASSWORD="Not ready yet"

echo "🎉 DEPLOYMENT COMPLETE!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔑 ArgoCD Access"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Username: admin"
echo "Password: $ARGOCD_PASSWORD"
echo ""
echo "To access:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  https://localhost:8080"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🌐 Cluster Info"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Cluster IP: $CLUSTER_IP"
echo ""
echo "Nodes:"
kubectl get nodes
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Next Steps"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Commit manifests to Git:"
echo "   git add .demo/manifests/"
echo "   git commit -m 'feat: configure applications'"
echo "   git push"
echo ""
echo "2. Watch ArgoCD sync your applications"
echo ""

print_info "✅ All done!"
