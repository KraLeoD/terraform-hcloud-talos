# GitOps Setup Guide with Cloudflare DNS, SOPS, and Authentik

This guide will help you set up a complete GitOps workflow with encrypted secrets, automated DNS management, and Authentik SSO.

## Prerequisites

- A Hetzner Cloud account with API token
- A domain managed by Cloudflare
- A Cloudflare API token with Zone.DNS (Edit) and Zone.Zone (Read) permissions
- Git repository for storing your manifests
- `kubectl`, `terraform`, `packer`, `sops`, and `age` installed

## Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│                  Your Git Repository                │
│  (Encrypted secrets with SOPS + age)               │
└──────────────────┬──────────────────────────────────┘
                   │
                   │ GitOps sync
                   ▼
┌─────────────────────────────────────────────────────┐
│                    ArgoCD                           │
│  (Watches repo, decrypts secrets, deploys apps)    │
└──────────────────┬──────────────────────────────────┘
                   │
                   │ Deploys to
                   ▼
┌─────────────────────────────────────────────────────┐
│              Kubernetes Cluster                     │
│                                                     │
│  ┌──────────────┐  ┌──────────────┐               │
│  │ External-DNS │  │   Traefik    │               │
│  │ (Cloudflare) │  │  (Ingress)   │               │
│  └──────────────┘  └──────────────┘               │
│                                                     │
│  ┌──────────────┐  ┌──────────────┐               │
│  │  PostgreSQL  │  │    Redis     │               │
│  └──────────────┘  └──────────────┘               │
│           │               │                         │
│           └───────┬───────┘                         │
│                   ▼                                 │
│           ┌──────────────┐                         │
│           │  Authentik   │                         │
│           │    (SSO)     │                         │
│           └──────────────┘                         │
└─────────────────────────────────────────────────────┘
                   │
                   │ Creates DNS records
                   ▼
            Cloudflare DNS
```

## Step 1: Initial Setup

### 1.1 Clone and Configure Repository

```bash
# Make sure you're in the repository root
cd terraform-hcloud-talos

# Make scripts executable
chmod +x setup-sops.sh deploy-enhanced.sh
```

### 1.2 Set Up SOPS Encryption

```bash
# Run the SOPS setup script
./setup-sops.sh
```

This will:
- Install `age` and `sops` if not already installed
- Generate an age encryption key at `.sops/age.agekey`
- Create `.sops.yaml` configuration
- Add the key to `.gitignore` (NEVER commit this file!)

**⚠️ CRITICAL: Backup your `.sops/age.agekey` file securely!**

Store it in:
- Password manager (1Password, Bitwarden, etc.)
- Encrypted backup
- Secure vault

Without this key, you cannot decrypt your secrets!

### 1.3 Build Talos Images

```bash
cd _packer
export HCLOUD_TOKEN='your-hetzner-token'
./create.sh
cd ..
```

## Step 2: Deploy the Cluster

```bash
./deploy-enhanced.sh
```

This script will:
1. Ask for your Cloudflare API token
2. Ask for your domain name
3. Deploy the infrastructure with Terraform
4. Export kubeconfig and talosconfig
5. Wait for cluster to be ready
6. Create necessary namespaces
7. Store SOPS age key in the cluster
8. Store Cloudflare credentials securely
9. Install ArgoCD
10. Deploy the app-root (GitOps bootstrap)

## Step 3: Prepare Your Manifests

### 3.1 Directory Structure

Create this structure in `.demo/manifests/apps/`:

```
.demo/manifests/apps/
├── external-dns/
│   └── application.yaml
├── authentik-dependencies/
│   ├── application.yaml
│   └── secrets/
│       └── postgres-secret.yaml (encrypted)
│       └── redis-secret.yaml (encrypted)
└── authentik/
    ├── application.yaml
    └── secrets/
        └── authentik-secret.yaml (encrypted)
```

### 3.2 Move Applications

```bash
# Copy the prepared application files
cp external-dns-app.yaml .demo/manifests/apps/external-dns/application.yaml
cp authentik-dependencies.yaml .demo/manifests/apps/authentik-dependencies/application.yaml
cp authentik-app.yaml .demo/manifests/apps/authentik/application.yaml
```

### 3.3 Create Encrypted Secrets

#### PostgreSQL Secret

```bash
mkdir -p .demo/manifests/apps/authentik-dependencies/secrets

cat > .demo/manifests/apps/authentik-dependencies/secrets/postgres-secret.yaml <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: postgresql-passwords
  namespace: authentik
type: Opaque
stringData:
  postgres-password: "your-strong-postgres-password-here"
  password: "your-strong-authentik-db-password-here"
EOF

# Encrypt it
sops --encrypt --in-place .demo/manifests/apps/authentik-dependencies/secrets/postgres-secret.yaml
```

#### Redis Secret

```bash
cat > .demo/manifests/apps/authentik-dependencies/secrets/redis-secret.yaml <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: redis-password
  namespace: authentik
type: Opaque
stringData:
  redis-password: "your-strong-redis-password-here"
EOF

# Encrypt it
sops --encrypt --in-place .demo/manifests/apps/authentik-dependencies/secrets/redis-secret.yaml
```

#### Authentik Secret

```bash
mkdir -p .demo/manifests/apps/authentik/secrets

cat > .demo/manifests/apps/authentik/secrets/authentik-secret.yaml <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: authentik-secrets
  namespace: authentik
type: Opaque
stringData:
  secret-key: "your-very-long-secret-key-at-least-50-characters-long-make-it-random"
  db-password: "your-strong-authentik-db-password-here"  # Same as PostgreSQL password
  redis-password: "your-strong-redis-password-here"  # Same as Redis password
EOF

# Encrypt it
sops --encrypt --in-place .demo/manifests/apps/authentik/secrets/authentik-secret.yaml
```

### 3.4 Update Kustomization

Update `.demo/manifests/apps/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - nginx
  - traefik.yaml
  - external-dns/application.yaml
  - authentik-dependencies/application.yaml
  - authentik-dependencies/secrets/postgres-secret.yaml
  - authentik-dependencies/secrets/redis-secret.yaml
  - authentik/application.yaml
  - authentik/secrets/authentik-secret.yaml
```

## Step 4: Update Application Configurations

### 4.1 Update External-DNS

Edit `.demo/manifests/apps/external-dns/application.yaml`:

```yaml
# In the helm values section, add:
domainFilters:
  - your-domain.com  # Replace with your actual domain
```

### 4.2 Update Authentik

Edit `.demo/manifests/apps/authentik/application.yaml`:

Replace these values:
- `secret_key`: Reference the secret you created
- `postgresql.password`: Reference the PostgreSQL secret
- `redis.password`: Reference the Redis secret
- `ingress.hosts[0].host`: Your actual subdomain (e.g., `auth.your-domain.com`)
- `ingress.tls[0].hosts[0]`: Same subdomain

Example with secret references:

```yaml
authentik:
  secret_key:
    valueFrom:
      secretKeyRef:
        name: authentik-secrets
        key: secret-key
  postgresql:
    password:
      valueFrom:
        secretKeyRef:
          name: authentik-secrets
          key: db-password
  redis:
    password:
      valueFrom:
        secretKeyRef:
          name: authentik-secrets
          key: redis-password
```

## Step 5: Deploy to Git and Sync

```bash
# Stage all changes
git add .demo/manifests/

# Commit
git commit -m "feat: add Cloudflare DNS, SOPS secrets, and Authentik"

# Push
git push origin main
```

ArgoCD will automatically:
1. Detect the changes
2. Decrypt the secrets using the age key
3. Deploy external-dns
4. Deploy PostgreSQL and Redis
5. Deploy Authentik

## Step 6: Configure DNS

### 6.1 Point Your Domain to the Cluster

Get your cluster IP:

```bash
cd .demo
terraform output cluster_endpoint
```

In Cloudflare:
1. Create an A record for your domain pointing to this IP
2. Create a wildcard A record `*.your-domain.com` pointing to this IP
3. Or let external-dns create specific records for each ingress

### 6.2 Verify External-DNS

```bash
# Check external-dns logs
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns

# Check if DNS records are being created
kubectl get ingress -A
```

## Step 7: Access Authentik

After deployment:

```bash
# Check Authentik status
kubectl get pods -n authentik

# Get the ingress
kubectl get ingress -n authentik

# Access Authentik
# Visit https://auth.your-domain.com
```

Default credentials:
- Email: `akadmin`
- Password: Check Authentik logs for the initial setup token

```bash
kubectl logs -n authentik -l app.kubernetes.io/name=authentik-server | grep "Bootstrap"
```

## Step 8: Running Docker Containers (as Kubernetes Deployments)

To run Docker containers in Kubernetes, create deployment manifests:

```bash
mkdir -p .demo/manifests/apps/my-app

cat > .demo/manifests/apps/my-app/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: my-app
        image: your-docker-image:tag
        ports:
        - containerPort: 8080
        env:
        - name: EXAMPLE_VAR
          value: "example-value"
        # For secrets:
        # - name: SECRET_VAR
        #   valueFrom:
        #     secretKeyRef:
        #       name: my-app-secrets
        #       key: secret-key
---
apiVersion: v1
kind: Service
metadata:
  name: my-app
  namespace: default
spec:
  selector:
    app: my-app
  ports:
  - port: 80
    targetPort: 8080
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  namespace: default
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    external-dns.alpha.kubernetes.io/target: "your-cluster-ip"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: traefik
  rules:
  - host: app.your-domain.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-app
            port:
              number: 80
  tls:
  - hosts:
    - app.your-domain.com
    secretName: my-app-tls
EOF
```

Add to kustomization and commit!

## Maintenance

### Viewing Encrypted Secrets

```bash
# View (decrypts in your editor)
sops .demo/manifests/apps/authentik/secrets/authentik-secret.yaml

# Edit (opens in $EDITOR)
sops .demo/manifests/apps/authentik/secrets/authentik-secret.yaml
```

### Rotating Secrets

1. Edit the encrypted file with `sops`
2. Update the values
3. Commit and push
4. ArgoCD will sync automatically

### Backing Up Age Key

```bash
# Export to a safe location
cp .sops/age.agekey ~/backup/age.agekey

# Or print to save elsewhere
cat .sops/age.agekey
```

### Adding Team Members

Share the age key securely with team members. They need to:

```bash
# Place the key
mkdir -p .sops
# Copy the key to .sops/age.agekey

# Set environment variable
export SOPS_AGE_KEY_FILE=".sops/age.agekey"

# Now they can decrypt
sops path/to/encrypted/file.yaml
```

## Troubleshooting

### ArgoCD Can't Decrypt Secrets

Check if the age key secret exists:

```bash
kubectl get secret sops-age -n argocd
```

If missing, recreate it:

```bash
kubectl create secret generic sops-age \
    --from-file=age.agekey=.sops/age.agekey \
    -n argocd
```

### External-DNS Not Creating Records

Check the logs:

```bash
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns
```

Common issues:
- Invalid Cloudflare API token
- Domain filter not matching
- Ingress missing the annotation

### Authentik Not Starting

Check dependencies:

```bash
kubectl get pods -n authentik
kubectl logs -n authentik -l app.kubernetes.io/name=postgresql
kubectl logs -n authentik -l app.kubernetes.io/name=redis
```

## Security Best Practices

1. **Never commit unencrypted secrets** - Always use SOPS
2. **Rotate secrets regularly** - Especially after team member changes
3. **Use strong passwords** - Generate with password managers
4. **Limit API token permissions** - Cloudflare token should only have DNS edit
5. **Backup your age key** - Store in multiple secure locations
6. **Review ArgoCD RBAC** - Limit who can access which applications
7. **Enable 2FA** - On Cloudflare, Hetzner, and Authentik
8. **Monitor logs** - Watch for unauthorized access attempts

## Next Steps

1. Set up cert-manager for automatic TLS certificates
2. Configure Authentik as OAuth2/OIDC provider
3. Integrate Authentik with your applications
4. Set up monitoring with Prometheus and Grafana
5. Configure backup solutions for databases
6. Implement network policies for additional security

## Resources

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [SOPS Documentation](https://github.com/getsops/sops)
- [External-DNS Documentation](https://github.com/kubernetes-sigs/external-dns)
- [Authentik Documentation](https://goauthentik.io/docs/)
- [Talos Linux Documentation](https://www.talos.dev/)
