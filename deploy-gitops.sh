#!/bin/bash
# GitOps deployment script
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

echo "🚀 GitOps Deployment for Kraleo Cluster"
echo "=========================================="
echo ""

# Step 1: Collect credentials
print_step "Step 1: Collecting Credentials"
echo ""

if [ -z "$HCLOUD_TOKEN" ]; then
    read -s -p "Enter your Hetzner Cloud API Token: " HCLOUD_TOKEN
    echo ""
    export HCLOUD_TOKEN
fi

if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
    read -s -p "Enter your Cloudflare API Token: " CLOUDFLARE_API_TOKEN
    echo ""
    export CLOUDFLARE_API_TOKEN
fi

read -p "Enter your domain (e.g., example.com): " DOMAIN
export DOMAIN

echo ""

# Step 2: Deploy infrastructure
print_step "Step 2: Deploying Infrastructure with Terraform"
cd .demo
terraform init
terraform apply
cd ..

echo ""

# Step 3: Bootstrap cluster
print_step "Step 3: Bootstrapping Cluster (Cilium, CCM)"
./bootstrap-cluster.sh

# CRITICAL: Export KUBECONFIG immediately after bootstrap
export KUBECONFIG="$SCRIPT_DIR/.demo/kubeconfig"
export TALOSCONFIG="$SCRIPT_DIR/.demo/talosconfig"

print_info "✅ KUBECONFIG exported: $KUBECONFIG"

# Verify kubectl works
if ! kubectl get nodes &>/dev/null; then
    print_error "kubectl cannot connect to cluster!"
    exit 1
fi

echo ""

# Step 4: Create namespaces
print_step "Step 4: Creating Namespaces"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace external-dns --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace authentik --dry-run=client -o yaml | kubectl apply -f -

print_info "✅ Namespaces created"
echo ""

# Step 5: Store secrets
print_step "Step 5: Storing Secrets in Cluster"

# SOPS age key
if [ -f .sops/age.agekey ]; then
    kubectl create secret generic sops-age \
        --from-file=age.agekey=.sops/age.agekey \
        -n argocd \
        --dry-run=client -o yaml | kubectl apply -f -
    print_info "✅ SOPS age key stored"
else
    print_warn "⚠️  No SOPS age key found at .sops/age.agekey"
fi

# Cloudflare credentials
kubectl create secret generic cloudflare-api-token \
    --from-literal=apiToken="$CLOUDFLARE_API_TOKEN" \
    -n external-dns \
    --dry-run=client -o yaml | kubectl apply -f -
print_info "✅ Cloudflare credentials stored"

# Domain config
kubectl create configmap external-dns-config \
    --from-literal=domain="$DOMAIN" \
    -n external-dns \
    --dry-run=client -o yaml | kubectl apply -f -
print_info "✅ Domain configuration stored"

echo ""

# Step 6: Install ArgoCD
print_step "Step 6: Installing ArgoCD"
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.11.4/manifests/install.yaml

print_info "⏳ Waiting for ArgoCD to be ready (this may take 2-3 minutes)..."
kubectl wait --for=condition=available --timeout=300s \
    deployment/argocd-server \
    -n argocd 2>/dev/null || print_warn "ArgoCD server not ready yet, continuing..."

kubectl wait --for=condition=available --timeout=300s \
    deployment/argocd-repo-server \
    -n argocd 2>/dev/null || print_warn "ArgoCD repo-server not ready yet, continuing..."

print_info "✅ ArgoCD installed"
echo ""

# Step 7: Install ArgoCD SOPS plugin
print_step "Step 7: Installing SOPS Plugin for ArgoCD"
if [ -f install-argocd-sops.sh ]; then
    ./install-argocd-sops.sh
    print_info "✅ SOPS plugin installed"
else
    print_warn "⚠️  install-argocd-sops.sh not found, skipping SOPS plugin"
fi

echo ""

# Step 8: Deploy app-root (GitOps bootstrap)
print_step "Step 8: Deploying GitOps Applications (App-Root)"

print_warn "⚠️  IMPORTANT: Make sure .demo/manifests/app-root.yaml has the correct Git repository URL!"
read -p "Have you updated app-root.yaml with your Git repo URL? (y/n) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_error "Please update .demo/manifests/app-root.yaml with your Git repository URL first!"
    echo "Then run: kubectl apply -f .demo/manifests/app-root.yaml"
    exit 1
fi

kubectl apply -f .demo/manifests/app-root.yaml
print_info "✅ App-root deployed - ArgoCD will now sync all applications from Git"

echo ""

# Step 9: Display access information
print_step "Step 9: Access Information"
echo ""

ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d) || ARGOCD_PASSWORD="Not ready yet"

echo "🔑 ArgoCD Admin Password: $ARGOCD_PASSWORD"
echo ""
echo "📊 Access ArgoCD:"
echo "  1. Port-forward: kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  2. Open: https://localhost:8080"
echo "  3. Login: admin / $ARGOCD_PASSWORD"
echo ""

CLUSTER_IP=$(cd .demo && terraform output -raw cluster_endpoint)
echo "🌐 DNS Configuration:"
echo "  Domain: $DOMAIN"
echo "  Point your DNS A record to: $CLUSTER_IP"
echo ""
echo "  Example DNS records to create in Cloudflare:"
echo "    A     @                 $CLUSTER_IP"
echo "    A     *.your-domain     $CLUSTER_IP"
echo ""

echo "📝 Environment Setup:"
echo "  For future sessions, run: source ./set-env.sh"
echo "  Or add to ~/.bashrc:"
echo "    export KUBECONFIG=$KUBECONFIG"
echo ""

# Add to bashrc if not already there
if ! grep -q "KUBECONFIG.*kraleo" ~/.bashrc 2>/dev/null; then
    echo "" >> ~/.bashrc
    echo "# Kraleo cluster kubeconfig" >> ~/.bashrc
    echo "export KUBECONFIG=$KUBECONFIG" >> ~/.bashrc
    print_info "✅ Added KUBECONFIG to ~/.bashrc"
fi

echo "✨ Deployment complete!"
echo ""
echo "🎯 Next Steps:"
echo "  1. Commit your manifests to Git"
echo "  2. Push to your repository"
echo "  3. ArgoCD will automatically deploy everything"
echo "  4. Monitor in ArgoCD UI: https://localhost:8080"
echo ""
echo "Cluster endpoint: $CLUSTER_IP"
