terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.86.0"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint #secrets.tfvars 
  api_token = var.proxmox_api_token
  insecure  = true
}