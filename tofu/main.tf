# Wazuh Deployment
module "wazuh_nodes" {
  source   = "./modules/wazuh_node"
  for_each = var.wazuh_nodes
    name     = each.key
    vm_id    = each.value.vm_id
    node     = "pve"
    cores    = each.value.cores
    memory   = each.value.memory
    disk     = each.value.disk
    ssh_public_key = var.ssh_public_key
}

# Sensor Deployment
module "sensor_nodes" {
  source   = "./modules/sensor_node"
  for_each = var.sensor_nodes
    name     = each.key
    vm_id    = each.value.vm_id
    node     = "pve"
    cores    = each.value.cores
    memory   = each.value.memory
    disk     = each.value.disk  
    ssh_public_key = var.ssh_public_key
    sniff_bridge   = var.sniff_bridge
}
