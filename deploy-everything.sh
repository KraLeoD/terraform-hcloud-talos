#!/bin/bash
# ONE-CLICK CLUSTER DEPLOYMENT
# This script destroys and redeploys everything automatically
# No need to run multiple scripts!

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

print_section "🚀 ONE-CLICK CLUSTER DEPLOYMENT"

echo "This script will:"
echo "  1. Destroy existing cluster (if any)"
echo "  2. Set up SOPS encryption (if needed)"
echo "  3. Generate encrypted secrets (if needed)"
echo "  4. Deploy fresh cluster with Terraform"
echo "  5. Install ArgoCD automatically"
echo "  6. Configure SOPS plugin"
echo "  7. Deploy app-root for GitOps"
echo ""
echo "⏱️  Estimated time: 10-15 minutes"
echo ""

read -p "Continue with full deployment? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

# ============================================
# PHASE 0: Collect Information
# ============================================

print_section "PHASE 0: Configuration"

# Check for Hetzner token
if [[ -z "${HCLOUD_TOKEN}" ]]; then
    print_warn "HCLOUD_TOKEN not found in environment"
    read -s -p "Enter your Hetzner Cloud API Token: " HCLOUD_TOKEN
    echo ""
    export HCLOUD_TOKEN
fi

# Check for Cloudflare token
if [[ -z "${CLOUDFLARE_API_TOKEN}" ]]; then
    print_warn "CLOUDFLARE_API_TOKEN not found in environment"
    read -s -p "Enter your Cloudflare API Token: " CLOUDFLARE_API_TOKEN
    echo ""
    export CLOUDFLARE_API_TOKEN
fi

# Get domain
read -p "Enter your domain (e.g., example.com): " DOMAIN
if [ -z "$DOMAIN" ]; then
    print_error "Domain is required!"
    exit 1
fi
export DOMAIN

print_info "✅ Configuration collected"

# ============================================
# PHASE 1: Cleanup
# ============================================

print_section "PHASE 1: Cleanup Existing Cluster"

if [ -d ".demo" ]; then
    print_step "Destroying existing cluster..."
    cd .demo
    if [ -f terraform.tfstate ]; then
        terraform destroy -auto-approve || print_warn "Destroy failed or nothing to destroy"
    else
        print_info "No existing cluster found"
    fi
    cd ..
    print_info "✅ Cleanup complete"
else
    print_info "No existing cluster found"
fi

# ============================================
# PHASE 2: SOPS Setup
# ============================================

print_section "PHASE 2: SOPS Encryption Setup"

if [ ! -f .sops/age.agekey ]; then
    print_step "Setting up SOPS..."
    
    # Create .sops directory
    mkdir -p .sops
    
    # Install age if needed
    if ! command -v age &> /dev/null; then
        print_info "Installing age..."
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            wget -q https://github.com/FiloSottile/age/releases/download/v1.1.1/age-v1.1.1-linux-amd64.tar.gz
            tar xzf age-v1.1.1-linux-amd64.tar.gz
            sudo mv age/age age/age-keygen /usr/local/bin/
            rm -rf age age-v1.1.1-linux-amd64.tar.gz
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            brew install age
        fi
    fi
    
    # Install sops if needed
    if ! command -v sops &> /dev/null; then
        print_info "Installing SOPS..."
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            wget -q https://github.com/getsops/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64
            sudo mv sops-v3.8.1.linux.amd64 /usr/local/bin/sops
            sudo chmod +x /usr/local/bin/sops
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            brew install sops
        fi
    fi
    
    # Generate age key
    print_info "Generating age encryption key..."
    age-keygen -o .sops/age.agekey
    
    AGE_PUBLIC_KEY=$(age-keygen -y .sops/age.agekey)
    
    # Create .sops.yaml
    cat > .sops.yaml <<EOF
# SOPS configuration for encrypting Kubernetes secrets
creation_rules:
  - path_regex: .demo/manifests/apps/.*/.*secret.*\.yaml$
    encrypted_regex: ^(data|stringData)$
    age: $AGE_PUBLIC_KEY
  - path_regex: .demo/manifests/apps/.*/secrets/.*\.yaml$
    encrypted_regex: ^(data|stringData)$
    age: $AGE_PUBLIC_KEY
EOF
    
    print_info "✅ SOPS encryption configured"
    print_warn "⚠️  IMPORTANT: Backup .sops/age.agekey securely!"
else
    print_info "✅ SOPS already configured"
fi

export SOPS_AGE_KEY_FILE="$SCRIPT_DIR/.sops/age.agekey"

# ============================================
# PHASE 3: Generate Secrets
# ============================================

print_section "PHASE 3: Generate Encrypted Secrets"

# Function to generate passwords
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
}

print_step "Generating secure passwords..."

POSTGRES_PASSWORD=$(generate_password)
AUTHENTIK_DB_PASSWORD=$(generate_password)
REDIS_PASSWORD=$(generate_password)
AUTHENTIK_SECRET_KEY=$(openssl rand -base64 64 | tr -d "=+/" | cut -c1-64)

# Create directories
mkdir -p .demo/manifests/apps/authentik-dependencies/secrets
mkdir -p .demo/manifests/apps/authentik/secrets

# Create PostgreSQL secret
cat > .demo/manifests/apps/authentik-dependencies/secrets/postgres-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: postgresql
  namespace: authentik
type: Opaque
stringData:
  postgres-password: "$POSTGRES_PASSWORD"
  password: "$AUTHENTIK_DB_PASSWORD"
EOF

# Create Redis secret
cat > .demo/manifests/apps/authentik-dependencies/secrets/redis-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: redis
  namespace: authentik
type: Opaque
stringData:
  redis-password: "$REDIS_PASSWORD"
EOF

# Create Authentik secret
cat > .demo/manifests/apps/authentik/secrets/authentik-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: authentik
  namespace: authentik
type: Opaque
stringData:
  secret-key: "$AUTHENTIK_SECRET_KEY"
  db-password: "$AUTHENTIK_DB_PASSWORD"
  redis-password: "$REDIS_PASSWORD"
EOF

# Encrypt all secrets
print_info "Encrypting secrets with SOPS..."
sops --encrypt --in-place .demo/manifests/apps/authentik-dependencies/secrets/postgres-secret.yaml
sops --encrypt --in-place .demo/manifests/apps/authentik-dependencies/secrets/redis-secret.yaml
sops --encrypt --in-place .demo/manifests/apps/authentik/secrets/authentik-secret.yaml

print_info "✅ Secrets generated and encrypted"

# ============================================
# PHASE 4: Deploy Cluster
# ============================================

print_section "PHASE 4: Deploy Cluster Infrastructure"

cd .demo

print_step "Running Terraform..."
terraform init
terraform apply -auto-approve

print_info "✅ Cluster deployed"

# Export configs
print_step "Exporting cluster configs..."
terraform output -raw kubeconfig > kubeconfig
terraform output -raw talosconfig > talosconfig
chmod 600 kubeconfig talosconfig

export KUBECONFIG="$SCRIPT_DIR/.demo/kubeconfig"
export TALOSCONFIG="$SCRIPT_DIR/.demo/talosconfig"

print_info "✅ Configs exported"

cd ..

# ============================================
# PHASE 5: Wait for Cluster
# ============================================

print_section "PHASE 5: Wait for Cluster Ready"

print_step "Waiting for nodes to be ready (may take 5-10 minutes)..."

MAX_ATTEMPTS=60
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if kubectl get nodes &>/dev/null; then
        print_info "Cluster API is accessible!"
        break
    fi
    ATTEMPT=$((ATTEMPT + 1))
    echo "  Attempt $ATTEMPT/$MAX_ATTEMPTS - waiting for cluster API..."
    sleep 10
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    print_error "Cluster API did not become accessible"
    exit 1
fi

# Wait for nodes
kubectl wait --for=condition=ready node --all --timeout=600s

print_info "✅ Cluster is ready!"
kubectl get nodes

# ============================================
# PHASE 6: Create Namespaces & Secrets
# ============================================

print_section "PHASE 6: Create Namespaces and Secrets"

print_step "Creating namespaces..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace external-dns --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace authentik --dry-run=client -o yaml | kubectl apply -f -

print_info "✅ Namespaces created"

print_step "Storing SOPS age key in cluster..."
kubectl create secret generic sops-age \
    --from-file=age.agekey=.sops/age.agekey \
    -n argocd \
    --dry-run=client -o yaml | kubectl apply -f -

print_info "✅ SOPS age key stored"

print_step "Storing Cloudflare credentials..."
kubectl create secret generic cloudflare-api-token \
    --from-literal=apiToken="$CLOUDFLARE_API_TOKEN" \
    -n external-dns \
    --dry-run=client -o yaml | kubectl apply -f -

print_info "✅ Cloudflare credentials stored"

# ============================================
# PHASE 7: Install ArgoCD
# ============================================

print_section "PHASE 7: Install ArgoCD"

print_step "Installing ArgoCD..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.11.4/manifests/install.yaml

print_info "⏳ Waiting for ArgoCD to be ready (this may take 2-3 minutes)..."
sleep 30  # Give pods time to start

kubectl wait --for=condition=available --timeout=300s \
    deployment/argocd-server \
    deployment/argocd-repo-server \
    -n argocd

print_info "✅ ArgoCD installed"

# ============================================
# PHASE 8: Configure SOPS Plugin
# ============================================

print_section "PHASE 8: Configure SOPS Plugin for ArgoCD"

print_step "Installing SOPS plugin..."

# Patch repo-server for SOPS
kubectl patch deployment argocd-repo-server -n argocd --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/initContainers",
    "value": [
      {
        "name": "install-sops",
        "image": "alpine:3.18",
        "command": [
          "sh",
          "-c",
          "apk add --no-cache curl && cd /custom-tools && curl -Lo sops https://github.com/getsops/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64 && chmod +x sops && curl -Lo age.tar.gz https://github.com/FiloSottile/age/releases/download/v1.1.1/age-v1.1.1-linux-amd64.tar.gz && tar xzf age.tar.gz && mv age/age age/age-keygen . && rm -rf age age.tar.gz && chmod +x age age-keygen"
        ],
        "volumeMounts": [
          {
            "mountPath": "/custom-tools",
            "name": "custom-tools"
          }
        ]
      }
    ]
  }
]' 2>/dev/null || print_warn "Init container may already exist"

# Add volumes
kubectl patch deployment argocd-repo-server -n argocd --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/volumes/-",
    "value": {
      "name": "custom-tools",
      "emptyDir": {}
    }
  }
]' 2>/dev/null || print_warn "Volume may already exist"

kubectl patch deployment argocd-repo-server -n argocd --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/volumes/-",
    "value": {
      "name": "sops-age",
      "secret": {
        "secretName": "sops-age"
      }
    }
  }
]' 2>/dev/null || print_warn "Volume may already exist"

# Add volume mounts
kubectl patch deployment argocd-repo-server -n argocd --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/volumeMounts/-",
    "value": {
      "mountPath": "/custom-tools",
      "name": "custom-tools"
    }
  }
]' 2>/dev/null || print_warn "Mount may already exist"

kubectl patch deployment argocd-repo-server -n argocd --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/volumeMounts/-",
    "value": {
      "name": "sops-age",
      "mountPath": "/sops",
      "readOnly": true
    }
  }
]' 2>/dev/null || print_warn "Mount may already exist"

# Add environment variables
kubectl patch deployment argocd-repo-server -n argocd --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/env/-",
    "value": {
      "name": "SOPS_AGE_KEY_FILE",
      "value": "/sops/age.agekey"
    }
  }
]' 2>/dev/null || print_warn "Env var may already exist"

kubectl patch deployment argocd-repo-server -n argocd --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/env/-",
    "value": {
      "name": "PATH",
      "value": "/custom-tools:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    }
  }
]' 2>/dev/null || print_warn "PATH may already be set"

print_info "⏳ Waiting for ArgoCD repo-server to restart..."
kubectl rollout status deployment/argocd-repo-server -n argocd --timeout=300s

print_info "✅ SOPS plugin configured"

# ============================================
# PHASE 9: Deploy App-Root
# ============================================

print_section "PHASE 9: Deploy GitOps Bootstrap"

print_warn "⚠️  Make sure you've updated .demo/manifests/app-root.yaml with your Git repository URL!"
read -p "Continue to deploy app-root? (y/n) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_step "Deploying app-root..."
    kubectl apply -f .demo/manifests/app-root.yaml
    print_info "✅ App-root deployed"
else
    print_warn "Skipped app-root deployment"
    echo "You can deploy it later with:"
    echo "  kubectl apply -f .demo/manifests/app-root.yaml"
fi

# ============================================
# PHASE 10: Access Information
# ============================================

print_section "PHASE 10: Access Information"

ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d) || ARGOCD_PASSWORD="Not ready yet"
CLUSTER_IP=$(cd .demo && terraform output -raw cluster_endpoint)

echo "🎉 DEPLOYMENT COMPLETE!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔑 ArgoCD Access"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Username: admin"
echo "Password: $ARGOCD_PASSWORD"
echo ""
echo "To access the UI:"
echo "  1. kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  2. Open: https://localhost:8080"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🌐 DNS Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Domain: $DOMAIN"
echo "Cluster IP: $CLUSTER_IP"
echo ""
echo "Create these DNS records in Cloudflare:"
echo "  A     @              $CLUSTER_IP"
echo "  A     *              $CLUSTER_IP"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📝 Environment Variables"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "export KUBECONFIG=$SCRIPT_DIR/.demo/kubeconfig"
echo "export TALOSCONFIG=$SCRIPT_DIR/.demo/talosconfig"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Next Steps"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Update .demo/manifests/app-root.yaml with your Git repo URL"
echo "2. Commit your manifests:"
echo "   git add .demo/manifests/"
echo "   git commit -m 'feat: configure cluster applications'"
echo "   git push origin main"
echo "3. Watch ArgoCD deploy everything automatically!"
echo ""

print_info "✅ All done! Your cluster is ready to use."
