proxmox_config = {
  node         = "pve-cluster-01"
  dataset_id   = "local-lvm"
  sniff_bridge = "vmbr1"
}


sensor_nodes = {
    # Sensor
  "Sensor" = { 
    vm_id   = 312
    cores   = 4
    memory  = 4096
    disk    = 64
    ip      = "192.168.100.46/24"
    gw      = "192.168.100.1" 
  }
}

wazuh_nodes = {
   # AIO
  "Wazuh-AIO" = { 
    vm_id  = 311 
    cores  = 4
    memory = 8192
    disk   = 64 
    ip     = "192.168.100.45/24"
    gw     = "192.168.100.1"
  }

   # wazuh distributed
#  "Indexer-1" = { 
#    vm_id = 321
#    cores = 2
#    memory = 6144
#    disk = 64 
#  }
#  "Manager-1" = { 
#    vm_id = 322
#    cores = 2
#    memory = 6144
#    disk = 32 
#  }
#  "Dashboard-1" = { 
#    vm_id = 323
#    cores = 2
#    memory = 6144
#    disk = 32 
#  }
}