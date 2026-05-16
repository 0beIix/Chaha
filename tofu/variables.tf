variable "wazuh_nodes" {
  type = map(object({
    vm_id  = number
    cores  = number
    memory = number
    disk   = number
    ip     = string
    gw     = string
  }))
  description = "All Wazuh nodes with resource specs"
}

variable "sensor_nodes" {
  type = map(object({
    vm_id  = number
    cores  = number
    memory = number
    disk   = number
    ip     = string
    gw     = string
  }))
  description = "All Sensor nodes with resource specs"
}


variable "proxmox_config" {
  type = object({
    node         = string
    dataset_id   = string
    sniff_bridge = string
    proxmox_api_token = string
    proxmox_endpoint = string
    ssh_public_key = string
  })
}

# Global Defaults (optional)
# variable "sniff_bridge" {
#   type    = string
#   default = "vmbr1"
# }

# variable "proxmox_node"  {
#   type    = string 
#   default = "pve"
#   }

# variable "datastore_id" { 
#   type = string 
#   default = "local-lvm"
#   description = "Datastore name like local-lvm or mounted volume"
#   }

# Secrets / Connection Info
# variable "proxmox_api_token" { 
#   type      = string
#   sensitive = true
#   }
  
# variable "proxmox_endpoint"  {
#   type = string 
#   }

# variable "ssh_public_key"    { 
#   type = string 
#   }

