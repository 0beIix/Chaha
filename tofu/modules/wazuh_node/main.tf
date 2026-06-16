resource "proxmox_virtual_environment_vm" "node" {
  name      = var.name
  vm_id     = var.vm_id
  node_name = var.node

  clone {
    vm_id = 5000
    full = true
  }

  initialization {
    datastore_id = var.datastore_id

    # Cloud-init configuration
    user_account {
      username = var.vm_user
      # password = var.vm_password
      keys     = [var.ssh_public_key]
    }

    ip_config {
      ipv4 {
        address = var.vm_ip  
        gateway = var.vm_gw 
      }
    }
  }

  cpu {
    cores = var.cores
    type = "host"
  }

  memory {
    dedicated = var.memory
  }

  disk {
    datastore_id = var.datastore_id
    size         = var.disk
    interface    = "scsi0"
  }

  network_device {
    bridge      = "vmbr0"
  }
  agent {
  enabled = true
  timeout = "3m"
  }
}