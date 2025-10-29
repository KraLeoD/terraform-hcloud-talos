#!/bin/bash
# Install SOPS plugin for ArgoCD
# This allows ArgoCD to automatically decrypt SOPS-encrypted secrets

set -e

echo "🔧 Installing SOPS plugin for ArgoCD..."

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is not installed"
    exit 1
fi

# Create ConfigMap with ArgoCD plugin configuration
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  # Enable the SOPS plugin
  configManagementPlugins: |
    - name: sops
      generate:
        command: ["sh", "-c"]
        args:
          - |
            if [ -f kustomization.yaml ] || [ -f kustomization.yml ] || [ -f Kustomization ]; then
              kustomize build . | sops -d /dev/stdin
            else
              sops -d .
            fi
EOF

echo "✅ ConfigMap created"

# Patch ArgoCD repo-server deployment to include SOPS and age
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: argocd-repo-server
  namespace: argocd
spec:
  template:
    spec:
      # Add init container to install SOPS and age
      initContainers:
      - name: install-sops
        image: alpine:3.18
        command:
          - sh
          - -c
          - |
            apk add --no-cache curl
            cd /custom-tools
            curl -Lo sops https://github.com/getsops/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64
            chmod +x sops
            curl -Lo age.tar.gz https://github.com/FiloSottile/age/releases/download/v1.1.1/age-v1.1.1-linux-amd64.tar.gz
            tar xzf age.tar.gz
            mv age/age age/age-keygen .
            rm -rf age age.tar.gz
            chmod +x age age-keygen
        volumeMounts:
        - mountPath: /custom-tools
          name: custom-tools
      
      containers:
      - name: argocd-repo-server
        # Add custom tools to PATH
        env:
        - name: PATH
          value: /custom-tools:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
        # Mount age key
        - name: SOPS_AGE_KEY_FILE
          value: /sops/age.agekey
        volumeMounts:
        - mountPath: /custom-tools
          name: custom-tools
        - mountPath: /sops
          name: sops-age
          readOnly: true
      
      volumes:
      - name: custom-tools
        emptyDir: {}
      - name: sops-age
        secret:
          secretName: sops-age
EOF

echo "✅ Deployment patched"

# Wait for rollout
echo "⏳ Waiting for ArgoCD repo-server to restart..."
kubectl rollout status deployment/argocd-repo-server -n argocd --timeout=300s

echo ""
echo "✅ SOPS plugin installed successfully!"
echo ""
echo "Now ArgoCD can automatically decrypt SOPS-encrypted secrets."
echo ""
echo "To use it in your Applications, add this annotation:"
echo ""
echo "metadata:"
echo "  annotations:"
echo "    argocd.argoproj.io/sync-options: UsePlugin=sops"
echo ""
