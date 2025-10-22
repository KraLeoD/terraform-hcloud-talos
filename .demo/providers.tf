terraform {
  required_version = ">= 1.8.0"

  required_providers {
    http = {
      source  = "hashicorp/http"
      version = ">= 3.5.0"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.1.3"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.35.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.11.0"
    }
  }
}

# kubectl provider is configured via the module's kubeconfig_data output
provider "kubectl" {
  host                   = module.talos.kubeconfig_data.host
  client_certificate     = module.talos.kubeconfig_data.client_certificate
  client_key             = module.talos.kubeconfig_data.client_key
  cluster_ca_certificate = module.talos.kubeconfig_data.cluster_ca_certificate
  load_config_file       = false
}

# kubernetes provider for reading secrets
provider "kubernetes" {
  host                   = module.talos.kubeconfig_data.host
  client_certificate     = module.talos.kubeconfig_data.client_certificate
  client_key             = module.talos.kubeconfig_data.client_key
  cluster_ca_certificate = module.talos.kubeconfig_data.cluster_ca_certificate
}
