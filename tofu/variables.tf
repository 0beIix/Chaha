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

# Secrets / Connection Info
variable "proxmox_api_token" { 
  type = string
  sensitive = true
  }
  
variable "proxmox_endpoint"  {
  type = string 
  }

variable "ssh_public_key"    { 
  type = string 
  }

# Global Defaults (optional)
variable "sniff_bridge" {
  type    = string
  default = "vmbr1"
}