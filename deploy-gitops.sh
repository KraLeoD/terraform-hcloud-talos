#!/bin/bash
# GitOps deployment script
set -e

cd "$(dirname "$0")"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
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

# Set environment
export KUBECONFIG=$(pwd)/.demo/kubeconfig

echo ""

# Step 4: Create namespaces
print_step "Step 4: Creating Namespaces"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace external-dns --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace authentik --dry-run=client -o yaml | kubectl apply -f -

echo ""

# Step 5: Store secrets
print_step "Step 5: Storing Secrets"

# SOPS age key
if [ -f .sops/age.agekey ]; then
    kubectl create secret generic sops-age \
        --from-file=age.agekey=.sops/age.agekey \
        -n argocd \
        --dry-run=client -o yaml | kubectl apply -f -
    print_info "✅ SOPS age key stored"
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

echo ""

# Step 6: Install ArgoCD
print_step "Step 6: Installing ArgoCD"
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.11.4/manifests/install.yaml

print_info "Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=available --timeout=300s \
    deployment/argocd-server \
    deployment/argocd-repo-server \
    -n argocd

echo ""

# Step 7: Install ArgoCD SOPS plugin
print_step "Step 7: Installing SOPS Plugin for ArgoCD"
if [ -f install-argocd-sops.sh ]; then
    ./install-argocd-sops.sh
fi

echo ""

# Step 8: Deploy app-root
print_step "Step 8: Deploying GitOps Applications"
kubectl apply -f .demo/manifests/app-root.yaml

print_info "✅ App-root deployed - ArgoCD will sync applications"

echo ""

# Step 9: Get ArgoCD password
print_step "Step 9: ArgoCD Access Information"
echo ""
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d 2>/dev/null || echo "Not ready yet")

echo "🔑 ArgoCD Admin Password: $ARGOCD_PASSWORD"
echo ""
echo "Access ArgoCD:"
echo "  1. Port-forward: kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  2. Open: https://localhost:8080"
echo "  3. Login: admin / $ARGOCD_PASSWORD"
echo ""

CLUSTER_IP=$(cd .demo && terraform output -raw cluster_endpoint)
echo "🌐 DNS Configuration:"
echo "  Domain: $DOMAIN"
echo "  Point your DNS A record to: $CLUSTER_IP"
echo ""

echo "✨ Deployment complete!"
echo ""
echo "Cluster endpoint: $CLUSTER_IP"
