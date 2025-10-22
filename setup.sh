#!/bin/bash
# Kraleo Cluster Setup Script
# This script helps you set up your Talos cluster on Hetzner Cloud

set -e

echo "=========================================="
echo "Kraleo Cluster Setup"
echo "=========================================="
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if required tools are installed
print_info "Checking for required tools..."

command -v terraform >/dev/null 2>&1 || {
    print_error "terraform is not installed. Please install it from https://www.terraform.io/downloads"
    exit 1
}

command -v packer >/dev/null 2>&1 || {
    print_error "packer is not installed. Please install it from https://www.packer.io/downloads"
    exit 1
}

print_info "All required tools are installed!"
echo ""

# Check for HCLOUD_TOKEN
if [[ -z "${HCLOUD_TOKEN}" ]]; then
    print_warn "HCLOUD_TOKEN environment variable is not set."
    echo "You'll need to create an API token at:"
    echo "https://console.hetzner.cloud/ -> Your Project -> Security -> API Tokens"
    echo ""
    read -s -p "Enter your Hetzner Cloud API token: " hcloud_token
    echo ""
    export HCLOUD_TOKEN="$hcloud_token"
    
    print_info "Token set for this session."
    print_warn "To persist it, add this to your ~/.bashrc or ~/.zshrc:"
    echo "export HCLOUD_TOKEN='your-token-here'"
    echo ""
else
    print_info "HCLOUD_TOKEN is set!"
fi

# Step 1: Build Talos images
print_info "Step 1: Building Talos images with Packer..."
echo "This will create Talos OS snapshots in your Hetzner Cloud project."
read -p "Continue? (y/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    cd _packer
    ./create.sh
    cd ..
    print_info "Talos images built successfully!"
else
    print_warn "Skipped Packer build. Make sure images exist before running Terraform!"
fi

echo ""

# Step 2: Initialize Terraform
print_info "Step 2: Initializing Terraform..."
cd .demo
terraform init

echo ""

# Step 3: Plan
print_info "Step 3: Planning Terraform deployment..."
echo "This will show you what resources will be created."
terraform plan

echo ""

# Step 4: Apply
print_info "Step 4: Ready to deploy your cluster!"
echo "This will:"
echo "  - Create 1 control plane node (cx22)"
echo "  - Create 2 worker nodes (cx22)"
echo "  - Configure networking and firewall"
echo "  - Install and configure Kubernetes"
echo ""
echo "Estimated cost: ~€15/month"
echo ""
read -p "Deploy the cluster? (y/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    terraform apply
    
    print_info "Cluster deployed!"
    echo ""
    
    # Step 5: Export configs
    print_info "Step 5: Exporting kubeconfig and talosconfig..."
    terraform output -raw kubeconfig > kubeconfig
    terraform output -raw talosconfig > talosconfig
    chmod 600 kubeconfig talosconfig
    
    print_info "Configuration files saved:"
    echo "  - kubeconfig: $(pwd)/kubeconfig"
    echo "  - talosconfig: $(pwd)/talosconfig"
    echo ""
    
    print_info "To use kubectl:"
    echo "  export KUBECONFIG=$(pwd)/kubeconfig"
    echo "  kubectl get nodes"
    echo ""
    
    print_info "To use talosctl:"
    echo "  export TALOSCONFIG=$(pwd)/talosconfig"
    echo "  talosctl --nodes <node-ip> version"
    echo ""
    
    print_info "Your cluster endpoint:"
    terraform output cluster_endpoint
    
    echo ""
    print_info "ArgoCD has been installed!"
    echo ""
    terraform output argocd_access_instructions
else
    print_warn "Deployment skipped."
fi

cd ..

echo ""
print_info "Setup complete! Happy tinkering! 🚀"
