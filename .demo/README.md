# Kraleo Cluster

A Talos Kubernetes cluster running on Hetzner Cloud.

## Quick Start

### Prerequisites

1. Install required tools:
   - [Terraform](https://www.terraform.io/downloads) >= 1.8.0
   - [Packer](https://www.packer.io/downloads)
   - [kubectl](https://kubernetes.io/docs/tasks/tools/)
   - [talosctl](https://www.talos.dev/latest/introduction/quickstart/#talosctl)

2. Get a Hetzner Cloud API token:
   - Go to https://console.hetzner.cloud/
   - Select your project
   - Go to Security → API Tokens
   - Generate a new token with Read & Write permissions

3. Set the token as an environment variable:
   ```bash
   export HCLOUD_TOKEN='your-token-here'
   ```

### Automated Setup

From the root of the repository, run:

```bash
chmod +x setup.sh
./setup.sh
```

This script will:
1. Build Talos images with Packer
2. Initialize Terraform
3. Show you the deployment plan
4. Deploy the cluster (with your confirmation)
5. Export kubeconfig and talosconfig files

### Manual Setup

If you prefer to run steps manually:

#### 1. Build Talos Images

```bash
cd _packer
./create.sh
cd ..
```

#### 2. Deploy with Terraform

```bash
cd .demo

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply the configuration
terraform apply

# Export configs
terraform output -raw kubeconfig > kubeconfig
terraform output -raw talosconfig > talosconfig
chmod 600 kubeconfig talosconfig
```

#### 3. Access Your Cluster

```bash
# Set kubeconfig
export KUBECONFIG=$(pwd)/kubeconfig

# Check nodes
kubectl get nodes

# Check pods
kubectl get pods -A

# Set talosconfig (for Talos-specific operations)
export TALOSCONFIG=$(pwd)/talosconfig

# Check Talos version
talosctl --nodes <node-ip> version
```

## Cluster Configuration

- **Name**: kraleo
- **Location**: Falkenstein, Germany (fsn1-dc14)
- **Control Planes**: 1x cx22 (2 vCPU, 4GB RAM)
- **Workers**: 2x cx22 (2 vCPU, 4GB RAM)
- **Kubernetes Version**: 1.30.3
- **Talos Version**: v1.11.0
- **CNI**: Cilium 1.16.2

## Cost

Approximately €15/month for the entire cluster.

## Common Operations

### Scale Workers

Edit `main.tf` and change `worker_count`:

```hcl
worker_count = 3  # Increase to 3 workers
```

Then apply:

```bash
terraform apply
```

### Access a Node with SSH (Emergency Only)

Talos doesn't use SSH by default, but if needed in rescue mode:

1. Put server in rescue mode via Hetzner Cloud Console
2. SSH using the rescue credentials
3. Remember to exit rescue mode when done

### Upgrade Kubernetes

Don't change `kubernetes_version` in Terraform! Instead, use talosctl:

```bash
talosctl upgrade-k8s --to 1.30.4
```

### Destroy the Cluster

```bash
cd .demo
terraform destroy
```

## Troubleshooting

### Can't connect to cluster

Check your firewall settings. The module auto-detects your IP, but if it changes:

1. Get your current IP: `curl https://ipv4.icanhazip.com`
2. Update firewall rules in Hetzner Cloud Console

### Nodes not ready

Check cilium status:

```bash
kubectl -n kube-system get pods -l k8s-app=cilium
kubectl -n kube-system logs -l k8s-app=cilium --tail=50
```

### Need to access Talos API

Get the control plane IP:

```bash
terraform output cluster_endpoint
```

Then use talosctl:

```bash
talosctl --nodes <ip> --endpoints <ip> dashboard
```

## Next Steps

- Deploy your first application
- Set up Ingress (nginx-ingress or Traefik)
- Add monitoring (Prometheus + Grafana)
- Set up persistent storage (Longhorn)
- Configure automatic backups

## Learning Resources

- [Talos Documentation](https://www.talos.dev/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Cilium Documentation](https://docs.cilium.io/)
- [Hetzner Cloud Docs](https://docs.hetzner.cloud/)
