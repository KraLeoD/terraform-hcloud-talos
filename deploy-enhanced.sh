#!/bin/bash
# Enhanced deployment script with Cloudflare DNS and secrets management

set -e

cd "$(dirname "$0")/.demo"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

echo "🚀 Deploying Kraleo cluster with Cloudflare DNS..."
echo ""

# Step 1: Collect Cloudflare credentials
print_step "Step 1: Cloudflare Configuration"
echo ""

if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
    print_info "Cloudflare API Token not found in environment."
    echo "You can create one at: https://dash.cloudflare.com/profile/api-tokens"
    echo "Required permissions: Zone.Zone (Read), Zone.DNS (Edit)"
    echo ""
    read -s -p "Enter your Cloudflare API Token: " CLOUDFLARE_API_TOKEN
    echo ""
    
    if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
        print_warn "No Cloudflare token provided. Skipping DNS setup."
        SETUP_DNS="false"
    else
        SETUP_DNS="true"
        export CLOUDFLARE_API_TOKEN
    fi
else
    print_info "Using Cloudflare API Token from environment"
    SETUP_DNS="true"
fi

if [ "$SETUP_DNS" = "true" ]; then
    read -p "Enter your domain (e.g., example.com): " DOMAIN
    
    if [ -z "$DOMAIN" ]; then
        print_error "Domain is required for DNS setup!"
        exit 1
    fi
    
    export DOMAIN
    print_info "Will setup DNS for: $DOMAIN"
fi

echo ""

# Step 2: Check for age encryption key
print_step "Step 2: Secrets Management"
echo ""

if [ ! -f ../.sops/age.agekey ]; then
    print_warn "Age encryption key not found!"
    echo "Run '../setup-sops.sh' first to set up secret encryption."
    read -p "Continue without encrypted secrets? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
    USE_SOPS="false"
else
    print_info "Age encryption key found"
    USE_SOPS="true"
    export SOPS_AGE_KEY_FILE="../.sops/age.agekey"
fi

echo ""

# Step 3: Deploy cluster with Terraform
print_step "Step 3: Deploying infrastructure with Terraform"
echo ""

terraform apply

echo ""
print_info "📝 Exporting cluster configs..."

# Export configs
terraform output -raw kubeconfig > kubeconfig
terraform output -raw talosconfig > talosconfig
chmod 600 kubeconfig talosconfig

# Set environment variables
export KUBECONFIG=$(pwd)/kubeconfig
export TALOSCONFIG=$(pwd)/talosconfig

print_info "✅ Configs exported!"
echo "KUBECONFIG: $(pwd)/kubeconfig"
echo "TALOSCONFIG: $(pwd)/talosconfig"
echo ""

# Save to shell config
if ! grep -q "KUBECONFIG.*kraleo" ~/.bashrc 2>/dev/null; then
    echo "" >> ~/.bashrc
    echo "# Kraleo cluster configs" >> ~/.bashrc
    echo "export KUBECONFIG=$(pwd)/kubeconfig" >> ~/.bashrc
    echo "export TALOSCONFIG=$(pwd)/talosconfig" >> ~/.bashrc
    print_info "Added config exports to ~/.bashrc"
fi

echo ""
print_step "Step 4: Waiting for cluster to be ready"
kubectl wait --for=condition=ready node --all --timeout=300s

echo ""

# Step 5: Create namespaces
print_step "Step 5: Creating namespaces"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace external-dns --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace authentik --dry-run=client -o yaml | kubectl apply -f -

echo ""

# Step 6: Set up SOPS in cluster
if [ "$USE_SOPS" = "true" ]; then
    print_step "Step 6: Setting up SOPS in cluster"
    
    # Create secret with age key
    kubectl create secret generic sops-age \
        --from-file=age.agekey=../.sops/age.agekey \
        -n argocd \
        --dry-run=client -o yaml | kubectl apply -f -
    
    print_info "✅ SOPS age key stored in cluster"
fi

echo ""

# Step 7: Create Cloudflare secret
if [ "$SETUP_DNS" = "true" ]; then
    print_step "Step 7: Creating Cloudflare secret"
    
    # Create the secret file
    cat > /tmp/cloudflare-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: cloudflare-api-token
  namespace: external-dns
type: Opaque
stringData:
  apiToken: "$CLOUDFLARE_API_TOKEN"
EOF
    
    # Apply the secret
    kubectl apply -f /tmp/cloudflare-secret.yaml
    rm /tmp/cloudflare-secret.yaml
    
    # Create domain configmap
    kubectl create configmap external-dns-config \
        --from-literal=domain="$DOMAIN" \
        -n external-dns \
        --dry-run=client -o yaml | kubectl apply -f -
    
    print_info "✅ Cloudflare credentials stored in cluster"
fi

echo ""

# Step 8: Install ArgoCD
print_step "Step 8: Installing ArgoCD"

kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.11.4/manifests/install.yaml

print_info "⏳ Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=available --timeout=300s \
    deployment/argocd-server \
    deployment/argocd-repo-server \
    -n argocd

echo ""

# Step 9: Deploy app-root
print_step "Step 9: Deploying GitOps applications"

kubectl apply -f manifests/app-root.yaml

print_info "✅ App-root deployed - ArgoCD will sync applications"

echo ""

# Step 10: Get ArgoCD password
print_step "Step 10: ArgoCD Access"
echo ""
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d 2>/dev/null || echo "Not ready yet")

echo "🔑 ArgoCD Admin Password: $ARGOCD_PASSWORD"
echo ""
echo "Access ArgoCD:"
echo "  1. Port-forward: kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  2. Open: https://localhost:8080"
echo "  3. Login: admin / $ARGOCD_PASSWORD"
echo ""

if [ "$SETUP_DNS" = "true" ]; then
    echo "🌐 DNS Configuration:"
    echo "  Domain: $DOMAIN"
    echo "  External-DNS will automatically create records for your ingresses"
    echo ""
    CLUSTER_IP=$(terraform output -raw cluster_endpoint)
    echo "  Make sure your domain's A record points to: $CLUSTER_IP"
    echo "  Or configure Cloudflare's proxied DNS to route to this IP"
    echo ""
fi

echo "✨ Deployment complete!"
echo ""
echo "Cluster endpoint: $(terraform output -raw cluster_endpoint)"
echo ""
echo "Next steps:"
echo "  1. Access ArgoCD UI to monitor application deployments"
echo "  2. Check that external-dns is creating DNS records"
echo "  3. Deploy additional applications via GitOps"
