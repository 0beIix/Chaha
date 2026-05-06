resource "proxmox_virtual_environment_vm" "node" {
  name      = var.name
  vm_id     = var.vm_id
  node_name = var.node

  clone {
    vm_id = 7000
    full  = true
  }

  network_device {
    bridge = "vmbr0" # Management / Wazuh agent traffic
  }

  network_device {
    # bridge = var.sniff_bridge # Mirror/Span port traffic
    bridge = var.sniff_bridge
  }

  initialization {
    datastore_id = "local"
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
    datastore_id = "local"
    size         = var.disk
    interface    = "scsi0"
  }
}
