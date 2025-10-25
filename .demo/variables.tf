variable "hcloud_token" {
  type        = string
  description = "Hetzner Cloud API token"
  sensitive   = true
}

# Netcup DNS Configuration Variables
variable "netcup_domain" {
  type        = string
  description = "Your Netcup domain (e.g., example.com)"
  sensitive   = false
}

variable "netcup_customer_id" {
  type        = string
  description = "Netcup Customer ID (found in CCP under API)"
  sensitive   = true
}

variable "netcup_api_key" {
  type        = string
  description = "Netcup API Key"
  sensitive   = true
}

variable "netcup_api_password" {
  type        = string
  description = "Netcup API Password"
  sensitive   = true
}
