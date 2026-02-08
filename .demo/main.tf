module "talos" {
  source = "../"

  # Versions
  talos_version      = "v1.11.0"
  kubernetes_version = "1.30.3"
  cilium_version     = "1.16.2"

  # Hetzner Cloud configuration
  hcloud_token = var.hcloud_token

  # Cluster configuration
  cluster_name    = "kraleo"
  datacenter_name = "fsn1-dc14"

  # Firewall - allow all (we'll restrict later)
  firewall_use_current_ip = false
  firewall_kube_api_source  = ["0.0.0.0/0"]
  firewall_talos_api_source = ["0.0.0.0/0"]

  # Control plane configuration
  control_plane_count       = 1
  control_plane_server_type = "cx23"

  # Worker configuration
  worker_count       = 1
  worker_server_type = "cx23"

  # Network configuration
  network_ipv4_cidr = "10.0.0.0/16"
  node_ipv4_cidr    = "10.0.1.0/24"
  pod_ipv4_cidr     = "10.0.16.0/20"
  service_ipv4_cidr = "10.0.8.0/21"

  # Disable floating IP and alias IP for simplicity
  enable_floating_ip = false
  enable_alias_ip = false
}

# Output the kubeconfig and talosconfig
output "talosconfig" {
  value     = module.talos.talosconfig
  sensitive = true
}

output "kubeconfig" {
  value     = module.talos.kubeconfig
  sensitive = true
}

output "cluster_endpoint" {
  value       = module.talos.public_ipv4_list[0]
  description = "Public IP of the control plane"
}

output "hetzner_network_id" {
  value = module.talos.hetzner_network_id
}
