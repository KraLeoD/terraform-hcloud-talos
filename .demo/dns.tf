# Netcup DNS Configuration
# This creates a wildcard DNS record pointing to the cluster's floating IP

# Get the floating IP from the talos module
locals {
  # Use floating IP if enabled, otherwise fall back to first control plane IP
  dns_target_ip = module.talos.public_ipv4_list[0]
}

# Create wildcard A record for the cluster
resource "netcup_dns_record" "wildcard" {
  zone        = var.netcup_domain
  hostname    = "*.kraleo"  # Creates *.kraleo.yourdomain.com
  type        = "A"
  destination = local.dns_target_ip
  
  depends_on = [module.talos]
}

# Optional: Create root record for the subdomain too
resource "netcup_dns_record" "root" {
  zone        = var.netcup_domain
  hostname    = "kraleo"  # Creates kraleo.yourdomain.com
  type        = "A"
  destination = local.dns_target_ip
  
  depends_on = [module.talos]
}

# Output the DNS records for verification
output "dns_records" {
  description = "DNS records created for the cluster"
  value = {
    wildcard = "*.kraleo.${var.netcup_domain} → ${local.dns_target_ip}"
    root     = "kraleo.${var.netcup_domain} → ${local.dns_target_ip}"
  }
}
