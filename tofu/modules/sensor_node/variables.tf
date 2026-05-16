# Values are specified in auto.tfvars

variable "name" {
  type        = string
  description = "VM name"
}

variable "vm_id" {
  type        = number
  description = "VM ID"
}

variable "node" {
  type        = string
  description = "Proxmox node name"
}

variable "cores" {
  type        = number
  description = "CPU cores"
}

variable "memory" {
  type        = number
  description = "Memory in MB"
}

variable "disk" {
  type        = number
  description = "Disk size in GB"
}

variable "datastore_id" { 
  type = string 
  description = "Datastore name like local-lvm or mounted volume"
  }
  
variable "vm_user" {
  type    = string
  default = "obelix"
}

variable "vm_ip" {
  type        = string
  description = "IP estática con máscara (ej: 192.168.1.50/24)"
}

variable "vm_gw" {
  type        = string
  description = "Gateway de la red"
}

variable "ssh_public_key" {
  type        = string
  description = "The public SSH key for the VM user"
}

variable "sniff_bridge" { 
  type = string 
  }

# variable "mac" {
#   type        = string
#   description = "MAC address"
# }
