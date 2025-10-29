#!/bin/bash
# Helper script to generate strong passwords and create encrypted secret files

set -e

# Check if sops is available
if ! command -v sops &> /dev/null; then
    echo "Error: sops is not installed. Run ./setup-sops.sh first"
    exit 1
fi

# Check if age key exists
if [ ! -f .sops/age.agekey ]; then
    echo "Error: age key not found. Run ./setup-sops.sh first"
    exit 1
fi

export SOPS_AGE_KEY_FILE=".sops/age.agekey"

# Function to generate a random password
generate_password() {
    local length=${1:-32}
    openssl rand -base64 $length | tr -d "=+/" | cut -c1-$length
}

echo "🔐 Generating secure passwords for your cluster..."
echo ""

# Generate passwords
POSTGRES_PASSWORD=$(generate_password 32)
AUTHENTIK_DB_PASSWORD=$(generate_password 32)
REDIS_PASSWORD=$(generate_password 32)
AUTHENTIK_SECRET_KEY=$(generate_password 64)

echo "Generated passwords (these will be encrypted):"
echo "  PostgreSQL Admin: ${POSTGRES_PASSWORD:0:8}... (hidden)"
echo "  Authentik DB User: ${AUTHENTIK_DB_PASSWORD:0:8}... (hidden)"
echo "  Redis: ${REDIS_PASSWORD:0:8}... (hidden)"
echo "  Authentik Secret Key: ${AUTHENTIK_SECRET_KEY:0:8}... (hidden)"
echo ""

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

echo "📝 Created PostgreSQL secret"

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

echo "📝 Created Redis secret"

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

echo "📝 Created Authentik secret"
echo ""

# Encrypt all secrets
echo "🔒 Encrypting secrets with SOPS..."
sops --encrypt --in-place .demo/manifests/apps/authentik-dependencies/secrets/postgres-secret.yaml
sops --encrypt --in-place .demo/manifests/apps/authentik-dependencies/secrets/redis-secret.yaml
sops --encrypt --in-place .demo/manifests/apps/authentik/secrets/authentik-secret.yaml

echo "✅ All secrets encrypted!"
echo ""
echo "⚠️  IMPORTANT: These passwords are now encrypted in the YAML files."
echo "   To view them later, use: sops <file>"
echo ""
echo "Next steps:"
echo "  1. Update the Helm values in the application.yaml files to reference these secrets"
echo "  2. Add the secrets to your kustomization.yaml"
echo "  3. Commit and push to trigger ArgoCD sync"
echo ""

# Create a backup of the passwords (encrypted)
BACKUP_FILE=".demo/.secrets-backup-$(date +%Y%m%d-%H%M%S).txt"
cat > "$BACKUP_FILE" <<EOF
# ENCRYPTED SECRETS BACKUP
# Generated: $(date)
# DO NOT COMMIT THIS FILE TO GIT

PostgreSQL Admin Password: $POSTGRES_PASSWORD
Authentik DB Password: $AUTHENTIK_DB_PASSWORD
Redis Password: $REDIS_PASSWORD
Authentik Secret Key: $AUTHENTIK_SECRET_KEY

# To use these, they are already encrypted in the YAML files.
# This backup is for emergency recovery only.
EOF

# Encrypt the backup
sops --encrypt --in-place "$BACKUP_FILE"

echo "📦 Created encrypted backup at: $BACKUP_FILE"
echo "   (Also encrypted with SOPS for safety)"
