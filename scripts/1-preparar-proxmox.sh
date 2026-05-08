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

#!/usr/bin/env bash

# Versión Automatizada (Silenciosa) del PVE Post Install
# Basado en el script de tteck

set -euo pipefail
shopt -s inherit_errexit nullglob

# --- Colores y Mensajes ---
RD=$(echo "\033[01;31m")
YW=$(echo "\033[33m")
GN=$(echo "\033[1;92m")
CL=$(echo "\033[m")
BFR="\\r\\033[K"
HOLD="-"
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"

msg_info() { echo -ne " ${HOLD} ${YW}$1..."; }
msg_ok() { echo -e "${BFR} ${CM} ${GN}$1${CL}"; }
msg_error() { echo -e "${BFR} ${CROSS} ${RD}$1${CL}"; }

# --- Funciones de Versión ---
get_pve_version() {
  pveversion | awk -F'/' '{print $2}' | awk -F'-' '{print $1}'
}

get_pve_major_minor() {
  local major minor
  IFS='.' read -r major minor _ <<<"$1"
  echo "$major $minor"
}

component_exists_in_sources() {
  grep -h -E "^[^#]*Components:[^#]*\b$1\b" /etc/apt/sources.list.d/*.sources 2>/dev/null | grep -q .
}

# --- Rutinas Comunes (Lo que antes eran menús) ---
post_routines_common() {
  # 1. Disable Subscription Nag
  msg_info "Disabling subscription nag"
  mkdir -p /usr/local/bin
  cat >/usr/local/bin/pve-remove-nag.sh <<'EOF'
#!/bin/sh
WEB_JS=/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
if [ -s "$WEB_JS" ] && ! grep -q NoMoreNagging "$WEB_JS"; then
    sed -i -e "/data\.status/ s/!//" -e "/data\.status/ s/active/NoMoreNagging/" "$WEB_JS"
fi
EOF
  chmod 755 /usr/local/bin/pve-remove-nag.sh
  cat >/etc/apt/apt.conf.d/no-nag-script <<'EOF'
DPkg::Post-Invoke { "/usr/local/bin/pve-remove-nag.sh"; };
EOF
  chmod 644 /etc/apt/apt.conf.d/no-nag-script
  msg_ok "Disabled subscription nag"

  # Reinstalar toolkit para aplicar parche
  apt --reinstall install proxmox-widget-toolkit &>/dev/null || true

  # 2. HA Services (En una instalación nueva/limpia solemos deshabilitarlos si es single node)
  if systemctl is-active --quiet pve-ha-lrm; then
    msg_info "Disabling high availability (Single Node Optimization)"
    systemctl disable -q --now pve-ha-lrm pve-ha-crm corosync || true
    msg_ok "Disabled high availability"
  fi

  # 3. Update System
  msg_info "Updating Proxmox VE (Patience)"
  apt update &>/dev/null
  apt -y dist-upgrade &>/dev/null
  msg_ok "Updated Proxmox VE"

  msg_ok "Completed Post Install Routines"
  
  # 4. Reboot (Opcional: Si quieres que reinicie solo, quita el '#' de abajo)
  # msg_info "Rebooting..." && sleep 2 && reboot
}

# --- Rutinas para PVE 8 (Bookworm) ---
start_routines_8() {
  msg_info "Correcting Proxmox VE Sources"
  cat <<EOF >/etc/apt/sources.list
deb http://deb.debian.org/debian bookworm main contrib
deb http://deb.debian.org/debian bookworm-updates main contrib
deb http://security.debian.org/debian-security bookworm-security main contrib
EOF
  echo 'APT::Get::Update::SourceListWarnings::NonFreeFirmware "false";' >/etc/apt/apt.conf.d/no-bookworm-firmware.conf
  
  msg_info "Disabling 'pve-enterprise' repository"
  [ -f /etc/apt/sources.list.d/pve-enterprise.list ] && sed -i 's/^deb/#deb/g' /etc/apt/sources.list.d/pve-enterprise.list
  
  msg_info "Enabling 'pve-no-subscription' repository"
  cat <<EOF >/etc/apt/sources.list.d/pve-install-repo.list
deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription
EOF

  msg_info "Correcting Ceph package repositories"
  cat <<EOF >/etc/apt/sources.list.d/ceph.list
# deb https://enterprise.proxmox.com/debian/ceph-quincy bookworm enterprise
deb http://download.proxmox.com/debian/ceph-quincy bookworm no-subscription
EOF
  msg_ok "Sources and Repositories configured"
  post_routines_common
}

# --- Rutinas para PVE 9 (Trixie) ---
start_routines_9() {
  msg_info "Migrating to deb822 sources (Proxmox 9)"
  rm -f /etc/apt/sources.list.d/*.list
  cat >/etc/apt/sources.list.d/debian.sources <<EOF
Types: deb
URIs: http://deb.debian.org/debian
Suites: trixie trixie-updates
Components: main contrib
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://security.debian.org/debian-security
Suites: trixie-security
Components: main contrib
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF

  msg_info "Adding 'pve-no-subscription' (deb822)"
  cat >/etc/apt/sources.list.d/proxmox.sources <<EOF
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF

  msg_info "Adding 'ceph-squid' no-subscription"
  cat >/etc/apt/sources.list.d/ceph.sources <<EOF
Types: deb
URIs: http://download.proxmox.com/debian/ceph-squid
Suites: trixie
Components: no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF

  post_routines_common
}

# --- Ejecución Principal ---
PVE_VERSION="$(get_pve_version)"
read -r PVE_MAJOR PVE_MINOR <<<"$(get_pve_major_minor "$PVE_VERSION")"

echo -e "${GN}Starting unattended Proxmox VE $PVE_MAJOR.x Post Install...${CL}"

if [[ "$PVE_MAJOR" == "8" ]]; then
  start_routines_8
elif [[ "$PVE_MAJOR" == "9" ]]; then
  start_routines_9
else
  msg_error "Unsupported version: $PVE_MAJOR"
  exit 1
fi

#########################
### PREPARAR SISTEMA ####
#########################


### ASEGURAR LLAVE SSH ###
msg_info "[*] Verificando llave SSH…"

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
msg_info "[*] Descargando imagen cloud a /tmp..."
PATH_TEMP_IMG="/tmp/$IMG_NAME"

# Descargamos solo si no existe para ahorrar ancho de banda
if [ ! -f "$PATH_TEMP_IMG" ]; then
    wget -q "$IMG_URL" -O "$PATH_TEMP_IMG"
fi

### VERIFICAR SI LA VM YA EXISTE ###
if qm status $TEMPLATE_VMID >/dev/null 2>&1; then
    msg_ok "[!] La VM $TEMPLATE_VMID ya existe. Saltando creación de template."
else
    ### CREAR VM ###
    msg_info "[*] Creando VM $TEMPLATE_VMID..."
    qm create $TEMPLATE_VMID \
      --name "$TEMPLATE_VM_NAME" \
      --memory $TEMPLATE_MEMORY \
      --cores $TEMPLATE_CORES \
      --net0 virtio,bridge=$TEMPLATE_BRIDGE

    ### IMPORTAR DISCO ###
    msg_info "[*] Importando disco..."
    qm importdisk $TEMPLATE_VMID "$PATH_TEMP_IMG" $TEMPLATE_STORAGE

fi

DISK_PATH="${TEMPLATE_STORAGE}:vm-$TEMPLATE_VMID-disk-0"

### LIMPIEZA ###
# rm -f "$PATH_TEMP_IMG"

### CONFIGURAR HARDWARE ###
msg_info "[*] Ajustando hardware…"
qm set $TEMPLATE_VMID --scsihw virtio-scsi-pci --scsi0 $DISK_PATH
qm set $TEMPLATE_VMID --ide2 ${TEMPLATE_STORAGE}:cloudinit
qm set $TEMPLATE_VMID --boot c --bootdisk scsi0
qm set $TEMPLATE_VMID --serial0 socket --vga serial0

### REDIMENSIONAR DISCO ###
echo "[*] Redimensionando disco a $TEMPLATE_DISK_SIZE…"
qm disk resize $TEMPLATE_VMID scsi0 "$TEMPLATE_DISK_SIZE"

### CONFIG CLOUD-INIT ###
echo "[*] Configurando Cloud-Init…"
qm set $TEMPLATE_VMID --ciuser "$CIUSER"
qm set $TEMPLATE_VMID --cipassword "$CIPASSWORD"
qm set $TEMPLATE_VMID --sshkeys "$PUB_KEY"

# DHCP para la interfaz principal
qm set $TEMPLATE_VMID --ipconfig0 ip=dhcp

### CONVERTIR A TEMPLATE ###
msg_info "[*] Convirtiendo VM en plantilla…"
qm template $TEMPLATE_VMID

msg_info "[*] Preparando Proxmox para IaC con Terraform…"

### Detectar automáticamente la IP de gestión de Proxmox
PROXMOX_IP=$(hostname -I | awk '{print $1}')
echo "[*] IP de Proxmox detectada: $PROXMOX_IP"


##########################
### CONFIGURAR USUARIO ###
##########################

# 1. Crear grupo (Validación exacta con awk para evitar falsos positivos)
if ! pveum group list --output-format json | jq -e ".[] | select(.groupid == \"$API_GROUP\")" >/dev/null 2>&1; then
    msg_info "Creando el grupo de Proxmox: $API_GROUP"
    pveum groupadd "$API_GROUP" -comment "Grupo de automatización para Terraform"
else
    msg_ok "El grupo $API_GROUP ya existe"
fi

# 2. Crear usuario (Validación exacta)
if ! pveum user list --output-format json | jq -e ".[] | select(.userid == \"$API_USER\")" >/dev/null 2>&1; then
    msg_info "Creando usuario API en Proxmox: $API_USER"
    pveum useradd "$API_USER" -comment "Usuario API para Terraform"
    # Añadimos el usuario al grupo (importante si quieres heredar permisos)
    pveum usermod "$API_USER" -group "$API_GROUP"
else
    msg_ok "El usuario $API_USER ya existe"
fi

# 3. Asignar permisos al grupo
msg_info "Asignando permisos de Administrador al grupo $API_GROUP"
pveum aclmod / -roles Administrator -groups "$API_GROUP"

# 4. Configurar Token API
msg_info "Configurando token API..."

# Verificamos si el token existe antes de intentar manipularlo
TOKEN_EXISTS=$(pveum user token list "$API_USER" --output-format json | jq -e ".[] | select(.tokenid == \"$API_TOKEN_NAME\")" >/dev/null 2>&1 && echo "yes" || echo "no")

if [ "$TOKEN_EXISTS" == "yes" ]; then
    msg_ok "El token $API_TOKEN_NAME ya existe. Rotando para obtener nuevo Secret..."
    pveum user token delete "$API_USER" "$API_TOKEN_NAME"
fi

# CREACIÓN ÚNICA (Solo una vez)
TOKEN_OUTPUT=$(pveum user token add "$API_USER" "$API_TOKEN_NAME" --privsep 1 --output-format json)
TOKEN_ID=$(echo "$TOKEN_OUTPUT" | jq -r '.fullid')
TOKEN_SECRET=$(echo "$TOKEN_OUTPUT" | jq -r '.value')

# 5. Asignar permisos al token (Usamos 'acl modify' o 'aclmod')
pveum aclmod / --roles Administrator --tokens "$TOKEN_ID"

msg_ok "Token configurado: $TOKEN_ID"
echo "#######################################################"
echo " GUARDA ESTE SECRET: $TOKEN_SECRET"
echo "#######################################################"
msg_info "[*] Guardando credenciales en /root/.proxmox-api"

### Guardar variables de entorno en archivo seguro
cat <<EOF >/root/.proxmox-api
export PM_API_URL="https://$PROXMOX_IP:8006/api2/json"
export PM_API_TOKEN_ID="$TOKEN_ID"
export PM_API_TOKEN_SECRET="$TOKEN_SECRET"
EOF

chmod 600 /root/.proxmox-api

echo "[*] Cargando las variables de entorno…"
source /root/.proxmox-api

msg_ok "[*] Preparación IaC completada correctamente."


######################
### Configurar Red ###
######################

msg_info "[*] Configurando persistencia para vmbr1 (Monitoreo)..."

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
