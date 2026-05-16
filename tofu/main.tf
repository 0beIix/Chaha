# Deploy by running in chaha folder
# tofu init
# tofu plan -var-file="secrets.tfvars"
# tofu apply -var-file="secrets.tfvars"

# !!! tofu destroy -var-file="secrets.tfvars" !!!

# Wazuh Deployment
module "wazuh_nodes" {
  source   = "./modules/wazuh_node"
  for_each = var.wazuh_nodes
    name     = each.key
    vm_id    = each.value.vm_id
    node     = each.value.proxmox_node
    cores    = each.value.cores
    memory   = each.value.memory
    disk     = each.value.disk
    datastore_id = each.value.datastore_id
    vm_ip    = each.value.ip
    vm_gw    = each.value.gw
    ssh_public_key = each.value.ssh_public_key
}

# Sensor Deployment
module "sensor_nodes" {
  source   = "./modules/sensor_node"
  for_each = var.sensor_nodes
    name     = each.key
    vm_id    = each.value.vm_id
    node     = each.value.proxmox_node
    cores    = each.value.cores
    memory   = each.value.memory
    disk     = each.value.disk  
    datastore_id = each.value.datastore_id
    vm_ip    = each.value.ip
    vm_gw    = each.value.gw
    ssh_public_key = each.value.ssh_public_key
    sniff_bridge   = each.value.sniff_bridge
}
