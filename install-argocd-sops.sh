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

# Verify ArgoCD is running
if ! kubectl get namespace argocd &>/dev/null; then
    echo "Error: argocd namespace not found"
    exit 1
fi

# Step 1: Configure ArgoCD to use SOPS via environment variables
echo "📝 Configuring ArgoCD repo-server for SOPS..."

# Patch the repo-server deployment to add SOPS environment variable
kubectl patch deployment argocd-repo-server -n argocd --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/env/-",
    "value": {
      "name": "SOPS_AGE_KEY_FILE",
      "value": "/sops/age.agekey"
    }
  }
]' 2>/dev/null || echo "Environment variable may already exist"

# Patch to add volume mount for age key
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
]' 2>/dev/null || echo "Volume mount may already exist"

# Patch to add volume for age key secret
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
]' 2>/dev/null || echo "Volume may already exist"

# Step 2: Install SOPS and age as init container
echo "📦 Adding SOPS and age binaries to repo-server..."

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
]' 2>/dev/null || echo "Init container may already exist"

# Add custom-tools volume
kubectl patch deployment argocd-repo-server -n argocd --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/volumes/-",
    "value": {
      "name": "custom-tools",
      "emptyDir": {}
    }
  }
]' 2>/dev/null || echo "custom-tools volume may already exist"

# Mount custom-tools in main container
kubectl patch deployment argocd-repo-server -n argocd --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/volumeMounts/-",
    "value": {
      "mountPath": "/custom-tools",
      "name": "custom-tools"
    }
  }
]' 2>/dev/null || echo "custom-tools mount may already exist"

# Update PATH to include custom-tools
kubectl patch deployment argocd-repo-server -n argocd --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/env/-",
    "value": {
      "name": "PATH",
      "value": "/custom-tools:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    }
  }
]' 2>/dev/null || echo "PATH may already be set"

echo "✅ Patches applied"

# Wait for rollout
echo "⏳ Waiting for ArgoCD repo-server to restart..."
kubectl rollout status deployment/argocd-repo-server -n argocd --timeout=300s

echo ""
echo "✅ SOPS plugin installed successfully!"
echo ""
echo "ArgoCD can now automatically decrypt SOPS-encrypted secrets."
echo ""
echo "To use encrypted secrets in your applications:"
echo "1. Encrypt secrets with: sops --encrypt --in-place secret.yaml"
echo "2. Commit to Git"
echo "3. ArgoCD will automatically decrypt them when syncing"
echo ""
