# Traefik Configuration

## Automated Setup

The `deploy-everything.sh` script automatically configures the `traefik-external` service with your node's public IP. This happens in Phase 9.5 after ArgoCD deploys the app-root.

## Manual Configuration (if needed)

If the automatic configuration fails or you deploy manually, update the service with your node's public IP:

```bash
# Get your node IP
kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}'
# Or from terraform
cd .demo && terraform output -raw cluster_endpoint

# Patch the service
kubectl patch service traefik-external -n traefik --type='json' \
  -p='[{"op": "replace", "path": "/spec/externalIPs", "value": ["YOUR_NODE_IP"]}]'
```

## Purpose

This service allows external-dns to discover the node IP and create DNS records (auth.kraleo.win, notes.kraleo.win) pointing to your cluster.
