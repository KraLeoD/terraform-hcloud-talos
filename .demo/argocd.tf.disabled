# ArgoCD installation after cluster is ready
# This follows the same pattern as the Proxmox repo

locals {
  argocd_version = "v2.11.4"
  argocd_manifest_url = "https://raw.githubusercontent.com/argoproj/argo-cd/${local.argocd_version}/manifests/install.yaml"
}

# Download ArgoCD manifests
data "http" "argocd_manifest" {
  url = local.argocd_manifest_url
  
  # Only fetch after cluster is ready
  depends_on = [module.talos]
}

# Parse the ArgoCD manifests into individual resources
data "kubectl_file_documents" "argocd" {
  content = data.http.argocd_manifest.response_body
}

# Create the argocd namespace first
resource "kubectl_manifest" "argocd_namespace" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: argocd
  YAML

  depends_on = [module.talos]
}

# Apply all ArgoCD manifests
resource "kubectl_manifest" "argocd" {
  for_each   = data.kubectl_file_documents.argocd.manifests
  yaml_body  = each.value
  
  # Use server-side apply for better handling of large resources
  server_side_apply = true
  
  depends_on = [
    kubectl_manifest.argocd_namespace
  ]
}

# Wait for ArgoCD to be ready
resource "time_sleep" "wait_for_argocd" {
  depends_on = [kubectl_manifest.argocd]
  
  create_duration = "30s"
}

# Output ArgoCD admin password
data "kubernetes_secret" "argocd_initial_password" {
  depends_on = [time_sleep.wait_for_argocd]
  
  metadata {
    name      = "argocd-initial-admin-secret"
    namespace = "argocd"
  }
}

output "argocd_admin_password" {
  description = "Initial admin password for ArgoCD"
  value       = try(nonsensitive(data.kubernetes_secret.argocd_initial_password.data.password), "pending...")
  sensitive   = false
}

output "argocd_access_instructions" {
  value = <<-EOT
    
    ╔════════════════════════════════════════════════════════════════╗
    ║                   ArgoCD Access Instructions                   ║
    ╚════════════════════════════════════════════════════════════════╝
    
    1. Port-forward to access the ArgoCD UI:
       kubectl port-forward svc/argocd-server -n argocd 8080:443
    
    2. Open your browser to: https://localhost:8080
       (Accept the self-signed certificate warning)
    
    3. Login with:
       Username: admin
       Password: ${try(nonsensitive(data.kubernetes_secret.argocd_initial_password.data.password), "Run 'terraform output argocd_admin_password' to get the password")}
    
    4. (Optional) Install ArgoCD CLI:
       curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
       sudo install -m 555 argocd /usr/local/bin/argocd
       rm argocd
    
    5. (Optional) Login via CLI:
       argocd login localhost:8080 --insecure
    
  EOT
}
