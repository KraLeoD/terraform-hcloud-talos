# Traefik Configuration

## Setup Instructions

After deploying the cluster, you MUST update the `service.yaml` file with your node's public IP:

```bash
# Get your node IP
kubectl get nodes -o wide
# Or from terraform
cd .demo && terraform output cluster_endpoint

# Edit service.yaml and replace YOUR_NODE_PUBLIC_IP_HERE with the actual IP
kubectl edit service traefik-external -n traefik
# Or update the file in Git and let ArgoCD sync
```

The service is required for external-dns to create DNS records pointing to your cluster.
