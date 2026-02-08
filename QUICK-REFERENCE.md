# Quick Reference Guide

## Common Commands

### SOPS Operations

```bash
# Encrypt a secret
sops --encrypt --in-place path/to/secret.yaml

# View encrypted secret
sops path/to/secret.yaml

# Edit encrypted secret (opens in $EDITOR)
sops path/to/secret.yaml

# Decrypt to stdout
sops -d path/to/secret.yaml

# Generate new age key
age-keygen -o .sops/age.agekey

# Get public key from private key
age-keygen -y .sops/age.agekey
```

### Kubernetes Operations

```bash
# Set context
export KUBECONFIG=.demo/kubeconfig

# Get all resources in namespace
kubectl get all -n <namespace>

# Watch pods
kubectl get pods -n <namespace> -w

# View logs
kubectl logs -n <namespace> <pod-name>
kubectl logs -n <namespace> -l app=<label> --tail=100 -f

# Describe resource
kubectl describe pod -n <namespace> <pod-name>

# Execute command in pod
kubectl exec -it -n <namespace> <pod-name> -- /bin/bash

# Port forward
kubectl port-forward -n <namespace> svc/<service-name> <local-port>:<remote-port>
```

### ArgoCD Operations

```bash
# Access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Visit: https://localhost:8080

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d

# Login via CLI
argocd login localhost:8080 --insecure

# List applications
argocd app list

# Sync application
argocd app sync <app-name>

# Get application status
argocd app get <app-name>

# Refresh application (check for changes)
argocd app refresh <app-name>

# View application logs
argocd app logs <app-name>

# Rollback application
argocd app rollback <app-name>
```

### External-DNS Operations

```bash
# Check logs
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns

# Check Cloudflare secret
kubectl get secret -n external-dns cloudflare-api-token -o yaml

# List ingresses being watched
kubectl get ingress -A

# Check DNS TXT records (for debugging)
dig TXT external-dns-<record-name>.your-domain.com
```

### Authentik Operations

```bash
# Check status
kubectl get pods -n authentik

# Get bootstrap token (first time)
kubectl logs -n authentik -l app.kubernetes.io/name=authentik-server | grep "Bootstrap"

# Check PostgreSQL
kubectl exec -it -n authentik postgresql-0 -- psql -U authentik -d authentik

# Check Redis
kubectl exec -it -n authentik redis-master-0 -- redis-cli

# Restart Authentik
kubectl rollout restart deployment -n authentik -l app.kubernetes.io/name=authentik
```

### Talos Operations

```bash
# Set context
export TALOSCONFIG=.demo/talosconfig

# Get node IP
terraform output -C .demo cluster_endpoint

# Check node version
talosctl --nodes <node-ip> version

# Get node logs
talosctl --nodes <node-ip> logs

# Dashboard
talosctl --nodes <node-ip> dashboard

# Health check
talosctl --nodes <node-ip> health

# Upgrade Kubernetes
talosctl upgrade-k8s --to 1.30.4
```

## Troubleshooting Steps

### Application Won't Start

1. Check ArgoCD sync status
   ```bash
   argocd app get <app-name>
   ```

2. Check pod status
   ```bash
   kubectl get pods -n <namespace>
   kubectl describe pod -n <namespace> <pod-name>
   ```

3. Check logs
   ```bash
   kubectl logs -n <namespace> <pod-name>
   ```

4. Check events
   ```bash
   kubectl get events -n <namespace> --sort-by='.lastTimestamp'
   ```

### Secrets Not Decrypting

1. Check age key is in cluster
   ```bash
   kubectl get secret sops-age -n argocd
   ```

2. Re-create if needed
   ```bash
   kubectl create secret generic sops-age \
       --from-file=age.agekey=.sops/age.agekey \
       -n argocd
   ```

3. Restart ArgoCD repo-server
   ```bash
   kubectl rollout restart deployment argocd-repo-server -n argocd
   ```

### DNS Not Working

1. Check external-dns logs
   ```bash
   kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns
   ```

2. Check Cloudflare credentials
   ```bash
   kubectl get secret -n external-dns cloudflare-api-token
   ```

3. Check ingress annotations
   ```bash
   kubectl get ingress -A -o yaml | grep external-dns
   ```

4. Verify in Cloudflare dashboard
   - Go to DNS section
   - Look for TXT records starting with "external-dns-"

### Database Connection Issues

1. Check PostgreSQL is running
   ```bash
   kubectl get pods -n authentik -l app.kubernetes.io/name=postgresql
   ```

2. Test connection
   ```bash
   kubectl run -it --rm psql-test --image=postgres:15 -- \
       psql -h postgresql -U authentik -d authentik
   ```

3. Check secrets
   ```bash
   sops -d .demo/manifests/apps/authentik-dependencies/secrets/postgres-secret.yaml
   ```

## File Locations

### Configuration Files
- Kubeconfig: `.demo/kubeconfig`
- Talosconfig: `.demo/talosconfig`
- Age key: `.sops/age.agekey` (NEVER commit!)
- SOPS config: `.sops.yaml`

### Manifests
- ArgoCD apps: `.demo/manifests/apps/`
- Secrets: `.demo/manifests/apps/*/secrets/`
- App root: `.demo/manifests/app-root.yaml`

### Terraform
- State: `.demo/terraform.tfstate`
- Variables: `.demo/main.tf`
- Outputs: Use `terraform output -C .demo`

## Important URLs

### Local Services
- ArgoCD: `https://localhost:8080` (after port-forward)
- Kubernetes API: `https://<cluster-ip>:6443`
- Talos API: `https://<cluster-ip>:50000`

### Your Services (replace your-domain.com)
- Authentik: `https://auth.your-domain.com`
- Your apps: `https://<subdomain>.your-domain.com`

### External
- Cloudflare Dashboard: `https://dash.cloudflare.com`
- Hetzner Console: `https://console.hetzner.cloud`
- ArgoCD Docs: `https://argo-cd.readthedocs.io`
- Authentik Docs: `https://goauthentik.io/docs`

## Emergency Procedures

### Lost Age Key
If you lose your `.sops/age.agekey`:
1. You CANNOT decrypt existing secrets
2. Generate new key: `age-keygen -o .sops/age.agekey`
3. Re-encrypt all secrets with new key
4. Update secret in cluster
5. THIS IS WHY YOU BACKUP THE KEY!

### Cluster Completely Down
1. Check Hetzner Cloud Console for server status
2. Use talosctl to check node health
3. Check Terraform state: `terraform state list -C .demo`
4. If needed, recreate: `terraform apply -C .demo`

### ArgoCD Locked Out
Reset admin password:
```bash
kubectl -n argocd delete secret argocd-initial-admin-secret
kubectl -n argocd scale deployment argocd-server --replicas=0
kubectl -n argocd scale deployment argocd-server --replicas=1
# Wait and get new password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

### Authentik Locked Out
Reset admin password via shell:
```bash
kubectl exec -it -n authentik deployment/authentik-server -- \
    ak create_admin_group
```

## Performance Tips

### Speed up ArgoCD sync
```bash
# Increase repo-server replicas
kubectl scale deployment argocd-repo-server -n argocd --replicas=2

# Decrease sync interval (in argocd-cm ConfigMap)
timeout.reconciliation: 60s  # Default is 180s
```

### Reduce resource usage
```bash
# Decrease replica counts in low-traffic times
kubectl scale deployment <name> -n <namespace> --replicas=1
```

### Monitor resource usage
```bash
# Install metrics-server (if not already)
kubectl top nodes
kubectl top pods -A
```

## Security Checklist

- [ ] Age key backed up securely
- [ ] Secrets encrypted with SOPS before committing
- [ ] Cloudflare API token has minimal permissions
- [ ] ArgoCD admin password changed from default
- [ ] Authentik admin password set
- [ ] TLS certificates configured (cert-manager)
- [ ] Network policies defined (optional)
- [ ] RBAC configured in ArgoCD
- [ ] Regular security updates scheduled
- [ ] Backup strategy defined

## Useful Aliases

Add to your `~/.bashrc` or `~/.zshrc`:

```bash
# Kubectl shortcuts
alias k='kubectl'
alias kg='kubectl get'
alias kd='kubectl describe'
alias kl='kubectl logs'
alias kx='kubectl exec -it'
alias kpf='kubectl port-forward'

# ArgoCD shortcuts
alias argocd-ui='kubectl port-forward svc/argocd-server -n argocd 8080:443'
alias argocd-pass='kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d'

# SOPS shortcuts
alias sops-edit='sops'
alias sops-view='sops -d'

# Context switching
alias use-kraleo='export KUBECONFIG=~/terraform-hcloud-talos/.demo/kubeconfig'
```
