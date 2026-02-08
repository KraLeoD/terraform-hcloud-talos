#!/bin/bash
# Setup SOPS with age for secret encryption

set -e

echo "🔐 Setting up SOPS with age for secret encryption..."

# Check if age is installed
if ! command -v age &> /dev/null; then
    echo "📦 Installing age..."
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        wget https://github.com/FiloSottile/age/releases/download/v1.1.1/age-v1.1.1-linux-amd64.tar.gz
        tar xzf age-v1.1.1-linux-amd64.tar.gz
        sudo mv age/age age/age-keygen /usr/local/bin/
        rm -rf age age-v1.1.1-linux-amd64.tar.gz
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        brew install age
    fi
fi

# Check if sops is installed
if ! command -v sops &> /dev/null; then
    echo "📦 Installing SOPS..."
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        wget https://github.com/getsops/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64
        sudo mv sops-v3.8.1.linux.amd64 /usr/local/bin/sops
        sudo chmod +x /usr/local/bin/sops
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        brew install sops
    fi
fi

# Create .sops directory if it doesn't exist
mkdir -p .sops

# Generate age key if it doesn't exist
if [ ! -f .sops/age.agekey ]; then
    echo "🔑 Generating age encryption key..."
    age-keygen -o .sops/age.agekey
    echo ""
    echo "✅ Age key generated at .sops/age.agekey"
    echo ""
    echo "⚠️  IMPORTANT: Backup this key securely!"
    echo "   Without it, you cannot decrypt your secrets."
    echo ""
fi

# Get the public key
AGE_PUBLIC_KEY=$(age-keygen -y .sops/age.agekey)

echo "📝 Your age public key:"
echo "$AGE_PUBLIC_KEY"
echo ""

# Create .sops.yaml configuration
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

echo "✅ Created .sops.yaml configuration"
echo ""

# Create example encrypted secret
mkdir -p .demo/manifests/apps/secrets-example

cat > .demo/manifests/apps/secrets-example/secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: example-secret
  namespace: default
type: Opaque
stringData:
  example-key: "this-will-be-encrypted"
  another-key: "also-encrypted"
EOF

echo "📝 Created example secret at .demo/manifests/apps/secrets-example/secret.yaml"
echo ""
echo "To encrypt it, run:"
echo "  sops --encrypt --in-place .demo/manifests/apps/secrets-example/secret.yaml"
echo ""
echo "To decrypt for editing:"
echo "  sops .demo/manifests/apps/secrets-example/secret.yaml"
echo ""

# Create gitignore entry for age key
if ! grep -q ".sops/age.agekey" .gitignore 2>/dev/null; then
    echo "" >> .gitignore
    echo "# SOPS encryption keys - NEVER commit these!" >> .gitignore
    echo ".sops/age.agekey" >> .gitignore
    echo "✅ Added .sops/age.agekey to .gitignore"
fi

echo ""
echo "🎉 SOPS setup complete!"
echo ""
echo "Next steps:"
echo "1. Install SOPS in your cluster (see instructions below)"
echo "2. Create a secret with your age key in the cluster"
echo "3. Deploy the SOPS secrets operator"
