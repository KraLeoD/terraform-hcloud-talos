#!/bin/bash
# Automated cluster deployment with config export

set -e

cd ~/terraform-hcloud-talos/.demo

echo "🚀 Deploying Kraleo cluster..."

# Prompt for Netcup DNS credentials if not already set
if [[ -z "${TF_VAR_netcup_domain}" ]]; then
    echo ""
    echo "📝 DNS Configuration"
    echo "To access your apps via custom domains, we'll configure DNS with Netcup."
    echo ""
    read -p "Enter your domain name (e.g., example.com): " netcup_domain
    read -p "Enter Netcup Customer ID: " netcup_customer_id
    read -p "Enter Netcup API Key: " netcup_api_key
    read -sp "Enter Netcup API Password: " netcup_api_password
    echo "" # Newline after password
    
    export TF_VAR_netcup_domain="$netcup_domain"
    export TF_VAR_netcup_customer_id="$netcup_customer_id"
    export TF_VAR_netcup_api_key="$netcup_api_key"
    export TF_VAR_netcup_api_password="$netcup_api_password"
    
    echo "✅ DNS credentials set for this session"
    echo ""
fi

# Apply Terraform
terraform apply

echo ""
echo "📝 Exporting cluster configs..."

# Export configs
terraform output -raw kubeconfig > kubeconfig
terraform output -raw talosconfig > talosconfig
chmod 600 kubeconfig talosconfig

# Set environment variables
export KUBECONFIG=$(pwd)/kubeconfig
export TALOSCONFIG=$(pwd)/talosconfig

echo "✅ Configs exported!"
echo ""
echo "KUBECONFIG: $(pwd)/kubeconfig"
echo "TALOSCONFIG: $(pwd)/talosconfig"
echo ""

# Save to shell config for persistence
echo "💾 Adding to ~/.bashrc for future sessions..."
if ! grep -q "KUBECONFIG.*kraleo" ~/.bashrc; then
    echo "" >> ~/.bashrc
    echo "# Kraleo cluster configs" >> ~/.bashrc
    echo "export KUBECONFIG=$(pwd)/kubeconfig" >> ~/.bashrc
    echo "export TALOSCONFIG=$(pwd)/talosconfig" >> ~/.bashrc
fi

echo ""
echo "⏳ Waiting for cluster to be ready..."
kubectl wait --for=condition=ready node --all --timeout=300s

echo ""
echo "⏳ Waiting for ArgoCD to install (via extraManifests)..."
sleep 30  # Give it time to start

# Wait for ArgoCD namespace to exist
while ! kubectl get namespace argocd &>/dev/null; do
    echo "Waiting for argocd namespace..."
    sleep 10
done

# Wait for ArgoCD pods
kubectl wait --for=condition=available --timeout=300s \
    deployment/argocd-server \
    deployment/argocd-repo-server \
    -n argocd 2>/dev/null || echo "⚠️  ArgoCD not ready yet, check manually"

echo ""
echo "📦 Applying app-root for GitOps..."
kubectl apply -f manifests/app-root.yaml

echo ""
echo "🔑 ArgoCD Admin Password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d 2>/dev/null || echo "Not ready yet"
echo ""

echo ""
echo "✨ Deployment complete!"
echo ""
echo "🌐 DNS Information:"
terraform output dns_records 2>/dev/null || echo "DNS records will be shown after apply completes"
echo ""
echo "Next steps:"
echo "  1. Wait a few minutes for DNS propagation"
echo "  2. Port-forward ArgoCD: kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  3. Access at: https://localhost:8080"
echo "  4. Login: admin / (password above)"
echo "  5. Your apps will be accessible at: https://<app>.kraleo.${TF_VAR_netcup_domain:-yourdomain.com}"
echo ""
echo "Cluster endpoint: $(terraform output -raw cluster_endpoint)"
