# GitOps Workflow with ArgoCD

This guide explains how to use ArgoCD to manage your Kubernetes applications in a GitOps way.

## What is GitOps?

GitOps is a way of managing your infrastructure and applications where:
- **Git is the single source of truth** - all your Kubernetes manifests live in Git
- **Automated deployment** - changes to Git trigger automatic updates to your cluster
- **Easy rollbacks** - just revert your Git commit to roll back changes
- **Audit trail** - Git history shows exactly what changed and when

## How It Works

1. **You commit** Kubernetes manifests to your Git repository
2. **ArgoCD watches** your repository for changes
3. **ArgoCD applies** changes automatically to your cluster
4. **ArgoCD keeps syncing** to ensure cluster state matches Git

## Setup Steps

### 1. Access ArgoCD UI

```bash
# Port-forward to access ArgoCD
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get the initial admin password
terraform output argocd_admin_password
```

Open https://localhost:8080 in your browser and login with:
- Username: `admin`
- Password: (from the terraform output)

### 2. Configure Your Repository

Edit `.demo/manifests/app-root.yaml` and update the `repoURL`:

```yaml
spec:
  source:
    repoURL: https://github.com/YOUR-USERNAME/YOUR-REPO
```

### 3. Create Your First Application

Create a simple nginx deployment:

```bash
mkdir -p .demo/manifests/apps/nginx
```

Create `.demo/manifests/apps/nginx/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx
  namespace: default
spec:
  selector:
    app: nginx
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
```

Update `.demo/manifests/apps/kustomization.yaml`:

```yaml
resources:
  - nginx/deployment.yaml
```

### 4. Commit and Push

```bash
git add .demo/manifests/
git commit -m "feat: add nginx application"
git push
```

### 5. Deploy the App-Root Application

This creates the "app of apps" pattern where ArgoCD manages applications from Git:

```bash
kubectl apply -f .demo/manifests/app-root.yaml
```

### 6. Watch ArgoCD Deploy

In the ArgoCD UI, you should see:
- The `app-root` application appear
- It will automatically deploy the nginx application
- The nginx deployment will be synced and healthy

## App-of-Apps Pattern

The app-root application is a special ArgoCD application that:
- Watches your `.demo/manifests/apps/` directory
- Automatically creates ArgoCD applications for each subdirectory
- Keeps everything in sync automatically

Benefits:
- Add a new app = just commit to Git
- Remove an app = delete from Git
- Update an app = commit changes to Git
- Everything is versioned and auditable

## Common ArgoCD Operations

### View Application Status

```bash
# Install ArgoCD CLI (optional)
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd /usr/local/bin/argocd
rm argocd

# Login via CLI
argocd login localhost:8080 --insecure

# List applications
argocd app list

# Get application details
argocd app get nginx

# View application logs
argocd app logs nginx
```

### Manual Sync

If automatic sync is disabled, you can sync manually:

```bash
argocd app sync nginx
```

### Rollback

```bash
# Rollback to previous version
argocd app rollback nginx
```

## Best Practices

1. **Use directories** for each application in `manifests/apps/`
2. **Use kustomize** for environment-specific configs
3. **Enable auto-sync** for automatic deployments
4. **Enable self-heal** so ArgoCD fixes manual changes
5. **Use Git branches** for testing changes before merging to main
6. **Review in ArgoCD UI** before syncing to production

## Example: Adding Metrics Server

1. Create the directory and manifest:

```bash
mkdir -p .demo/manifests/apps/metrics-server
```

Create `.demo/manifests/apps/metrics-server/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.7.1/components.yaml

patches:
  - patch: |-
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: metrics-server
        namespace: kube-system
      spec:
        template:
          spec:
            containers:
            - name: metrics-server
              args:
              - --cert-dir=/tmp
              - --secure-port=10250
              - --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname
              - --kubelet-use-node-status-port
              - --metric-resolution=15s
              - --kubelet-insecure-tls
```

2. Update `.demo/manifests/apps/kustomization.yaml`:

```yaml
resources:
  - nginx/deployment.yaml
  - metrics-server/kustomization.yaml
```

3. Commit and push:

```bash
git add .demo/manifests/apps/
git commit -m "feat: add metrics-server"
git push
```

ArgoCD will automatically detect the changes and deploy metrics-server!

## Troubleshooting

### Application Won't Sync

Check the application status:
```bash
argocd app get <app-name>
```

View detailed sync status:
```bash
argocd app sync <app-name> --dry-run
```

### Out of Sync

ArgoCD shows "OutOfSync" when Git doesn't match cluster state. This can happen if:
- Someone made manual changes with `kubectl`
- The application hasn't synced yet

Fix it by:
1. Enabling auto-sync and self-heal
2. Manually syncing: `argocd app sync <app-name>`

### Repository Connection Issues

Ensure your repository is public or configure credentials:
```bash
argocd repo add https://github.com/YOUR-USERNAME/YOUR-REPO --username YOUR-USERNAME --password YOUR-TOKEN
```

## Next Steps

- Explore ArgoCD's [ApplicationSets](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/) for managing multiple applications
- Set up [ArgoCD Notifications](https://argo-cd.readthedocs.io/en/stable/operator-manual/notifications/) for Slack/email alerts
- Learn about [Progressive Delivery](https://argo-cd.readthedocs.io/en/stable/user-guide/progressive-delivery/) with Argo Rollouts
- Configure [RBAC](https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/) for team access
