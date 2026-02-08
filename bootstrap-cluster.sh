#!/bin/bash
# Bootstrap script - applies initial cluster components
set -e

cd "$(dirname "$0")/.demo"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "🚀 Bootstrapping Kraleo cluster..."
echo ""

# Export configs
print_info "Exporting kubeconfig and talosconfig..."
terraform output -raw kubeconfig > kubeconfig
terraform output -raw talosconfig > talosconfig
chmod 600 kubeconfig talosconfig

export KUBECONFIG=$(pwd)/kubeconfig
export TALOSCONFIG=$(pwd)/talosconfig

print_info "Configs exported to:"
echo "  KUBECONFIG: $(pwd)/kubeconfig"
echo "  TALOSCONFIG: $(pwd)/talosconfig"
echo ""

# Wait for nodes to be ready
print_info "Waiting for nodes to be ready (this may take 5-10 minutes)..."
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

# Wait for nodes to be ready
kubectl wait --for=condition=ready node --all --timeout=600s || {
    print_error "Nodes did not become ready"
    kubectl get nodes
    exit 1
}

print_info "✅ Nodes are ready!"
kubectl get nodes
echo ""

# Apply Cilium
print_info "Installing Cilium CNI..."
kubectl apply -f - <<EOF
---
# Cilium will be installed via Helm or manifests
# For now, let's check if it's already there from Talos
EOF

# Check if Cilium is already running (Talos might have installed it)
if kubectl get pods -n kube-system -l k8s-app=cilium &>/dev/null; then
    print_info "Cilium is already present (installed by Talos/Terraform)"
else
    print_warn "Cilium not found, installing manually..."
    # Install Cilium using Helm
    if ! command -v helm &> /dev/null; then
        print_error "Helm is not installed. Please install Helm first."
        exit 1
    fi
    
    helm repo add cilium https://helm.cilium.io/
    helm repo update
    
    helm install cilium cilium/cilium --version 1.16.2 \
        --namespace kube-system \
        --set operator.replicas=1 \
        --set ipam.mode=kubernetes \
        --set k8sServiceHost=127.0.0.1 \
        --set k8sServicePort=7445 \
        --wait
fi

# Create hcloud secret
print_info "Creating Hetzner Cloud secret..."
NETWORK_ID=$(terraform output -raw hetzner_network_id)

kubectl create secret generic hcloud \
    --namespace kube-system \
    --from-literal=token="$HCLOUD_TOKEN" \
    --from-literal=network="$NETWORK_ID" \
    --dry-run=client -o yaml | kubectl apply -f -

# Apply Hetzner CCM
print_info "Installing Hetzner Cloud Controller Manager..."
kubectl apply -f https://github.com/hetznercloud/hcloud-cloud-controller-manager/releases/latest/download/ccm-networks.yaml

print_info "Waiting for CCM to be ready..."
kubectl wait --for=condition=available --timeout=300s \
    deployment/hcloud-cloud-controller-manager \
    -n kube-system || print_warn "CCM not ready yet, continuing..."

echo ""
print_info "✅ Cluster bootstrap complete!"
echo ""
kubectl get nodes
kubectl get pods -n kube-system
echo ""
print_info "Ready for ArgoCD installation!"
