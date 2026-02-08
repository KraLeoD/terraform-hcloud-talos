#!/bin/bash
# Automated cluster deployment with config export

set -e

cd ~/terraform-hcloud-talos/.demo

echo " Deploying Kraleo cluster..."

# Apply Terraform
terraform apply

echo ""
echo " Exporting cluster configs..."

# Export configs
terraform output -raw kubeconfig > kubeconfig
terraform output -raw talosconfig > talosconfig
chmod 600 kubeconfig talosconfig

# Set environment variables
export KUBECONFIG=$(pwd)/kubeconfig
export TALOSCONFIG=$(pwd)/talosconfig

echo " Configs exported!"
echo ""
echo "KUBECONFIG: $(pwd)/kubeconfig"
echo "TALOSCONFIG: $(pwd)/talosconfig"
echo ""

# Save to shell config for persistence
echo " Adding to ~/.bashrc for future sessions..."
if ! grep -q "KUBECONFIG.*kraleo" ~/.bashrc; then
    echo "" >> ~/.bashrc
    echo "# Kraleo cluster configs" >> ~/.bashrc
    echo "export KUBECONFIG=$(pwd)/kubeconfig" >> ~/.bashrc
    echo "export TALOSCONFIG=$(pwd)/talosconfig" >> ~/.bashrc
fi

echo ""
echo " Waiting for cluster to be ready..."
kubectl wait --for=condition=ready node --all --timeout=300s

echo ""
echo " Installing ArgoCD..."

# Clean up any ArgoCD in default namespace (from extraManifests)
kubectl delete all -n default -l app.kubernetes.io/part-of=argocd 2>/dev/null || true

# Create argocd namespace
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Install ArgoCD properly
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.11.4/manifests/install.yaml

echo " Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=available --timeout=300s \
    deployment/argocd-server \
    deployment/argocd-repo-server \
    -n argocd

echo ""
echo " Applying app-root for GitOps..."
kubectl apply -f manifests/app-root.yaml

echo ""
echo " ArgoCD Admin Password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d 2>/dev/null || echo "Not ready yet"
echo ""

echo ""
echo " Deployment complete!"
echo ""
echo "Next steps:"
echo "  1. Port-forward ArgoCD: kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  2. Access at: https://localhost:8080"
echo "  3. Login: admin / (password above)"
echo ""
echo "Cluster endpoint: $(terraform output -raw cluster_endpoint)"
