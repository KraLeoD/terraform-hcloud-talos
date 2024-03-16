resource "talos_machine_secrets" "this" {}

locals {
  cert_SANs = concat([
    for control_plane_primary_ip in hcloud_primary_ip.control_planes : control_plane_primary_ip.ip_address
    ], [
    for control_plane_local_ip in local.control_plane_ips : control_plane_local_ip
    ]
  )
  cluster_endpoint = "https://${local.control_plane_ips[0]}:6443"
  cluster_config_patches = [
    templatefile("${path.module}/patches/cluster-patch.yaml.tmpl", {
      allow_scheduling_on_control_planes = var.worker_count <= 0,
      cert_SANs                          = join(",", local.cert_SANs)
    })
  ]
}

data "talos_machine_configuration" "control_plane" {
  count            = var.control_plane_count
  talos_version    = var.talos_version
  cluster_name     = var.cluster_name
  cluster_endpoint = local.cluster_endpoint
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  config_patches = concat(
    local.cluster_config_patches,
    [
      templatefile("${path.module}/patches/machine-patch.yaml.tmpl", {
        node_ipv4_public          = hcloud_primary_ip.control_planes[count.index].ip_address
        node_ipv4_private         = local.control_plane_ips[count.index]
        node_ipv4_private_cidr    = local.control_plane_cidr
        cluster_ipv4_private_cidr = var.network_ipv4_cidr
      })
    ]
  )
  docs     = false
  examples = false
}

data "talos_machine_configuration" "worker" {
  count            = var.worker_count
  talos_version    = var.talos_version
  cluster_name     = var.cluster_name
  cluster_endpoint = local.cluster_endpoint
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  config_patches = concat(
    local.cluster_config_patches,
    [
      templatefile("${path.module}/patches/machine-patch.yaml.tmpl", {
        node_ipv4_public          = hcloud_primary_ip.workers[count.index].ip_address
        node_ipv4_private         = local.worker_ips[count.index]
        node_ipv4_private_cidr    = local.worker_cidr
        cluster_ipv4_private_cidr = var.network_ipv4_cidr
      })
    ]
  )
  docs     = false
  examples = false
}

resource "talos_machine_bootstrap" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoint             = hcloud_server.control_planes[0].ipv4_address
  node                 = hcloud_server.control_planes[0].ipv4_address
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints = [
    for server in hcloud_server.control_planes : server.ipv4_address
  ]
}

data "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = hcloud_server.control_planes[0].ipv4_address
  depends_on = [
    talos_machine_bootstrap.this
  ]
}
