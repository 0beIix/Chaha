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

variable "vm_user" {
  type    = string
  default = "obelix"
}

# variable "vm_password" {
#   type      = string
#   sensitive = true # This hides the password in the console output/logs
# }

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
