#!/bin/bash
set -e

###########################
### VARIABLES EDITABLES ###
###########################

### Interfaz de monitoreo
IFACE_MON="enp1s0" # <--- Cambia esto por la NIC física que recibirá el tráfico

### Datos para el template (solo afectan a Puppet-Master VM)
TEMPLATE_VMID=5000
TEMPLATE_VM_NAME="ubuntu-cloud"
TEMPLATE_MEMORY=4096
TEMPLATE_CORES=2
TEMPLATE_STORAGE="local-lvm"
TEMPLATE_DISK_SIZE="10G"
TEMPLATE_BRIDGE="vmbr0"

# Datos para VM Master
MASTER_VMID=999
MASTER_VM_NAME="Puppet-Master"

IMG_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
IMG_NAME="ubuntu-cloudimg.img"

SSH_KEY_NAME="puppet_master_ed25519"
CIUSER="ubuntu"
CIPASSWORD="ubuntu"

### Definir nombres de usuario/grupo/token en proxmox
API_USER="terraform@pve"
API_GROUP="terraform-group"
API_TOKEN_NAME="terraform-token"


########################
### NO EDITAR DEBAJO ###
########################

#########################
### PREPARAR SISTEMA ####
#########################

# ... (tu código anterior de DEBIAN_CODENAME) ...

### --- Configuración de Repositorios PVE ---
echo "Configurando repositorios No-Subscription..."

# Comentar el repositorio enterprise de PVE
if [ -f /etc/apt/sources.list.d/pve-enterprise.list ]; then
    sed -i 's/^deb/#deb/g' /etc/apt/sources.list.d/pve-enterprise.list
fi

# Crear el repositorio No-Subscription de PVE
cat <<EOF > /etc/apt/sources.list.d/pve-no-subscription.list
deb http://download.proxmox.com/debian/pve $DEBIAN_CODENAME pve-no-subscription
EOF

### --- Configuración de Repositorios Ceph (Squid/Quincy/etc) ---
echo "Configurando repositorios de Ceph..."

# Comentar el repositorio enterprise de Ceph (el que te da el error 401)
if [ -f /etc/apt/sources.list.d/ceph.list ]; then
    sed -i 's/^deb/#deb/g' /etc/apt/sources.list.d/ceph.list
fi

# Añadir el repositorio No-Subscription de Ceph (versión Squid para Trixie/PVE 9 o Quincy para Bookworm/PVE 8)
# Nota: Proxmox usualmente usa una variable para la versión de Ceph, pero 'squid' es la actual para Trixie.
cat <<EOF > /etc/apt/sources.list.d/ceph-no-subscription.list
deb http://download.proxmox.com/debian/ceph-squid $DEBIAN_CODENAME no-subscription
EOF

### --- Limpieza de Avisos y Actualización ---
# Eliminar el aviso de "No Subscription"
sed -E -i.bak "s/(Ext.Msg.show\(\{)/void\(\1/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js

# Reiniciar el servicio web para aplicar cambios visuales (opcional pero recomendado)
# systemctl restart pveproxy

echo "Actualizando sistema..."
apt update && apt dist-upgrade -y

### ASEGURAR LLAVE SSH ###
echo "[*] Verificando llave SSH…"

SSH_DIR="$HOME/.ssh"
PUB_KEY="$SSH_DIR/${SSH_KEY_NAME}.pub"
PRIV_KEY="$SSH_DIR/${SSH_KEY_NAME}"

if [[ ! -f "$PUB_KEY" ]]; then
    echo "[*] No existe llave SSH dedicada — generando nueva…"
    mkdir -p "$SSH_DIR"
    ssh-keygen -t ed25519 -f "$PRIV_KEY" -C "puppet-master-key" -N ""
else
    echo "[*] Llave SSH ya existe: $PUB_KEY"
fi

### DESCARGAR DEPENDENCIAS ###
apt update
apt install -y jq

### DESCARGAR IMAGEN A TEMPORAL ###
echo "[*] Descargando imagen cloud a /tmp..."
PATH_TEMP_IMG="/tmp/$IMG_NAME"

# Descargamos solo si no existe para ahorrar ancho de banda
if [ ! -f "$PATH_TEMP_IMG" ]; then
    wget -q "$IMG_URL" -O "$PATH_TEMP_IMG"
fi

### CREAR VM ###
echo "[*] Creando VM $VMID…"
qm create $TEMPLATE_VMID \
  --name $TEMPLATE_VM_NAME \
  --memory $TEMPLATE_MEMORY \
  --cores $TEMPLATE_CORES \
  --net0 virtio,bridge=$TEMPLATE_BRIDGE

### IMPORTAR DISCO ###
echo "[*] Importando disco…"
qm importdisk $TEMPLATE_VMID "$PATH_TEMP_IMG" $TEMPLATE_STORAGE

### LIMPIEZA ###
rm -f "$PATH_TEMP_IMG"

DISK_PATH="${TEMPLATE_STORAGE}:vm-$TEMPLATE_VMID-disk-0"

### CONFIGURAR HARDWARE ###
echo "[*] Ajustando hardware…"
qm set $TEMPLATE_VMID --scsihw virtio-scsi-pci --scsi0 $DISK_PATH
qm set $TEMPLATE_VMID --ide2 ${TEMPLATE_STORAGE}:cloudinit
qm set $TEMPLATE_VMID --boot c --bootdisk scsi0
qm set $TEMPLATE_VMID --serial0 socket --vga serial0

### REDIMENSIONAR DISCO ###
echo "[*] Redimensionando disco a $DISK_SIZE…"
qm disk resize $TEMPLATE_VMID scsi0 "$TEMPLATE_DISK_SIZE"

### CONFIG CLOUD-INIT ###
echo "[*] Configurando Cloud-Init…"
qm set $TEMPLATE_VMID --ciuser "$CIUSER"
qm set $TEMPLATE_VMID --cipassword "$CIPASSWORD"
qm set $TEMPLATE_VMID --sshkeys "$PUB_KEY"

# DHCP para la interfaz principal
qm set $TEMPLATE_VMID --ipconfig0 ip=dhcp

### CONVERTIR A TEMPLATE ###
echo "[*] Convirtiendo VM en plantilla…"
qm template $TEMPLATE_VMID

echo "[*] Preparando Proxmox para IaC con Terraform…"

### Detectar automáticamente la IP de gestión de Proxmox
PROXMOX_IP=$(hostname -I | awk '{print $1}')
echo "[*] IP de Proxmox detectada: $PROXMOX_IP"


##########################
### CONFIGURAR USUARIO ###
##########################

### Crear grupo si no existe
if ! pveum group list | grep -q "$API_GROUP"; then
    echo "[*] Creando el grupo de Proxmox: $API_GROUP"
    pveum groupadd "$API_GROUP" -comment "Grupo de automatización para Terraform"
else
    echo "[*] El grupo $API_GROUP ya existe"
fi

### Crear usuario si no existe
if ! pveum user list | grep -q "$API_USER"; then
    echo "[*] Creando usuario API en Proxmox: $API_USER"
    pveum useradd "$API_USER" -comment "Usuario API para Terraform"
else
    echo "[*] El usuario $API_USER ya existe"
fi

### Asignar permisos de Administrador al grupo
echo "[*] Asignando permisos de Administrador al grupo $API_GROUP"
pveum aclmod / -roles Administrator -groups "$API_GROUP"

### Crear o actualizar token API
echo "[*] Configurando token API..."
# Borramos el token anterior si existe para generar uno nuevo y capturar el Secret
pveum user token delete "$API_USER" "$API_TOKEN_NAME" || true
TOKEN_OUTPUT=$(pveum user token add "$API_USER" "$API_TOKEN_NAME" --privsep 1 --output-format json)
TOKEN_ID=$(echo "$TOKEN_OUTPUT" | jq -r '.fullid')
TOKEN_SECRET=$(echo "$TOKEN_OUTPUT" | jq -r '.value')

TOKEN_OUTPUT=$(pveum user token add "$API_USER" "$API_TOKEN_NAME" --privsep 1 --output-format json)

### Asignar permisos de Administrador al token
pveum acl modify / --roles Administrator --tokens "$TOKEN_ID"

echo "[*] Token API creado: $TOKEN_ID"
echo "[*] Guardando credenciales en /root/.proxmox-api"

### Guardar variables de entorno en archivo seguro
cat <<EOF >/root/.proxmox-api
export PM_API_URL="https://$PROXMOX_IP:8006/api2/json"
export PM_API_TOKEN_ID="$TOKEN_ID"
export PM_API_TOKEN_SECRET="$TOKEN_SECRET"
EOF

chmod 600 /root/.proxmox-api

echo "[*] Cargando las variables de entorno…"
source /root/.proxmox-api

echo "[*] Preparación IaC completada correctamente."


######################
### Configurar Red ###
######################

echo "[*] Configurando persistencia para vmbr1 (Monitoreo)..."

if ! grep -q "iface vmbr1" /etc/network/interfaces; then
    echo "[*] Añadiendo vmbr1 a /etc/network/interfaces..."
    
    cat <<EOF >> /etc/network/interfaces

auto $IFACE_MON
iface $IFACE_MON inet manual
    ovs_type OVSPort
    ovs_bridge vmbr1
# Interfaz fisica para Sniffing

auto vmbr1
iface vmbr1 inet manual
    bridge-ports $IFACE_MON
    bridge-stp off
    bridge-fd 0
# Bridge para IDS/Sensor (Sin IP)
EOF

    echo "[*] Aplicando cambios de red..."
    ifup vmbr1 || true
    # Forzar modo promiscuo
    ip link set $IFACE_MON promisc on
else
    echo "[*] La configuración de vmbr1 ya existe en /etc/network/interfaces"
fi


################
### Crear VM ###
################

qm clone $TEMPLATE_VMID $MASTER_VMID --name $MASTER_VM_NAME --full


###############
### Resumen ###
###############

echo ""
echo "==============================================="
echo "    Plantilla Cloud-Init creada con éxito      "
echo "-----------------------------------------------"
echo " TEMPLATE VMID:         $TEMPLATE_VMID"
echo " Nombre:       $TEMPLATE_VM_NAME"
echo " Disco:        $TEMPLATE_DISK_SIZE"
echo " Usuario CI:   $CIUSER"
echo " Contraseña:   $CIPASSWORD"
echo "-----------------------------------------------"
echo " Llave SSH utilizada:"
echo "   Pública : $PUB_KEY"
echo "   Privada : $PRIV_KEY"
echo "-----------------------------------------------"
echo " Para conectarte luego:"
echo "   ssh -i $PRIV_KEY $CIUSER@<IP>"
echo "-----------------------------------------------"
echo "            Configuración para IaC             "
echo "-----------------------------------------------"
echo "IP de Proxmox:  $PROXMOX_IP"
echo "Usuario creado: $API_USER"
echo "Archivo de config en '/root/.proxmox-api'"
echo "==============================================="
