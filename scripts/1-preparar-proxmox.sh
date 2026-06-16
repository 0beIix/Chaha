#!/usr/bin/env bash
set -euo pipefail
shopt -s inherit_errexit nullglob

###########################
### CONFIGURACIÓN GLOBAL ##
###########################

### Cloud-init download
readonly IMG_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
#readonly IMG_URL="http://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
readonly IMG_NAME="ubuntu-cloudimg-amd64.img"
readonly TEMPLATE_DISK_SIZE="10G"

### Cloud-init VM Template
readonly TEMPLATE_VMID="5000" # keep 5000 or update tofu accordingly
readonly MASTER_VMID="999"

readonly TEMPLATE_VM_NAME="ubuntu-cloud"
readonly MASTER_VM_NAME="Puppet-Master"

### Cloud-init VM template specs
readonly TEMPLATE_MEMORY="4096"
readonly TEMPLATE_CORES="2"
readonly TEMPLATE_STORAGE="local-lvm"
readonly TEMPLATE_BRIDGE="vmbr0"

### Cloud-init user
readonly CI_USER="chaha"
readonly CI_PASSWORD_ENABLED="true"
readonly CI_PASSWORD="ChangeMe123!"

### SSH
readonly SSH_KEY_NAME="puppet_master_ed25519"
readonly SSH_KEY_COMMENT="puppet-master-key"

### Api opentofu
readonly API_USER="tofu@pve"
readonly API_GROUP="tofu-group"
readonly API_TOKEN_NAME="tofu-token"

### Red monitoreo
readonly MONITORING_INTERFACE="ens19"
readonly MONITORING_BRIDGE="vmbr1"


########################
### No Editar debajo ###
########################

### Global variables
CURRENT_STAGE="startup"
trap 'msg_error "Falló en etapa: ${CURRENT_STAGE}"' ERR
readonly API_CREDENTIALS_FILE="/root/.proxmox-api"

##############
### Logger ###
##############

readonly RD="\033[01;31m"
readonly YW="\033[33m"
readonly GN="\033[1;92m"
readonly BL="\033[1;34m"
readonly CL="\033[m"

msg_info() {
    echo -e "${BL}[INFO]${CL} $1"
}

msg_ok() {
    echo -e "${GN}[OK]${CL} $1"
}

msg_warn() {
    echo -e "${YW}[WARN]${CL} $1"
}

msg_error() {
    echo -e "${RD}[ERROR]${CL} $1"
}

############
### Main ###
############

main() {
    check_root
    check_proxmox_environment

    install_required_packages

    validate_network_interface "$MONITORING_INTERFACE"

    setup_ssh_keys

    create_cloudinit_template

    configure_proxmox_api_access

    configure_monitoring_bridge
    enable_monitoring_promiscuous_mode

    create_iac_master_vm

    print_summary
}

####################
### Validaciones ###
####################

check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        msg_error "Este script debe ejecutarse como root"
        exit 1
    fi
}

check_proxmox_environment() {
    if ! command -v pveversion >/dev/null 2>&1; then
        msg_error "No se detectó un entorno Proxmox VE"
        exit 1
    fi
}

validate_network_interface() {
    local iface="$1"

    if ! ip link show "$iface" >/dev/null 2>&1; then
        msg_error "La interfaz '$iface' no existe"
        exit 1
    fi
}


####################
### Dependencias ###
####################

readonly REQUIRED_PACKAGES=(
    jq
    curl
    wget
    openssh-client
)

install_required_packages() {
    CURRENT_STAGE="packages"

    msg_info "Instalando dependencias requeridas"

    apt-get update -qq

    local missing_packages=()

    for package in "${REQUIRED_PACKAGES[@]}"; do
        if ! dpkg -s "$package" >/dev/null 2>&1; then
            missing_packages+=("$package")
        fi
    done

    if [[ ${#missing_packages[@]} -eq 0 ]]; then
        msg_ok "Todas las dependencias ya están instaladas"
        return
    fi

    apt-get install -y "${missing_packages[@]}"

    msg_ok "Dependencias instaladas correctamente"
}

######################
### Configurar SSH ###
######################

readonly SSH_DIR="$HOME/.ssh"
readonly SSH_PRIVATE_KEY_PATH="${SSH_DIR}/${SSH_KEY_NAME}"
readonly SSH_PUBLIC_KEY_PATH="${SSH_PRIVATE_KEY_PATH}.pub"
readonly SSH_CONFIG_FILE="${SSH_DIR}/config"

setup_ssh_keys() {
    CURRENT_STAGE="ssh"

    msg_info "Configurando llaves SSH"

    ensure_ssh_directory
    generate_ssh_keypair
    validate_ssh_permissions
    configure_ssh_client
    load_ssh_public_key
    
    msg_ok "Configuración SSH completada"
}

ensure_ssh_directory() {
    if [[ ! -d "$SSH_DIR" ]]; then
        msg_info "Creando directorio SSH"

        mkdir -p "$SSH_DIR"
    fi

    chmod 700 "$SSH_DIR"
}

generate_ssh_keypair() {
    if [[ -f "$SSH_PUBLIC_KEY_PATH" ]]; then
        msg_ok "La llave SSH ya existe"

        return
    fi

    msg_info "Generando llave SSH ED25519"

    ssh-keygen \
        -t ed25519 \
        -f "$SSH_PRIVATE_KEY_PATH" \
        -C "$SSH_KEY_COMMENT" \
        -N "" \
        -q

    msg_ok "Llave SSH generada correctamente"
}

validate_ssh_permissions() {
    chmod 600 "$SSH_PRIVATE_KEY_PATH"
    chmod 644 "$SSH_PUBLIC_KEY_PATH"

    msg_ok "Permisos SSH verificados"
}

configure_ssh_client() {
    if [[ ! -f "$SSH_CONFIG_FILE" ]]; then
        touch "$SSH_CONFIG_FILE"

        chmod 600 "$SSH_CONFIG_FILE"
    fi

    if grep -q "IdentityFile ${SSH_PRIVATE_KEY_PATH}" "$SSH_CONFIG_FILE"; then
        msg_ok "La configuración SSH ya existe"

        return
    fi

    msg_info "Configurando cliente SSH"

    cat >> "$SSH_CONFIG_FILE" <<EOF

Host *
    IdentityFile ${SSH_PRIVATE_KEY_PATH}

EOF

    msg_ok "Cliente SSH configurado correctamente"
}

load_ssh_public_key() {
    SSH_PUBLIC_KEY_CONTENT=$(<"$SSH_PUBLIC_KEY_PATH")

    if [[ -z "$SSH_PUBLIC_KEY_CONTENT" ]]; then
        msg_error "No se pudo leer la llave pública SSH"

        exit 1
    fi
}

###########################
### Cloud-init template ###
###########################

ensure_cloud_image() {
    CURRENT_STAGE="cloud_image"

    local image_path="/tmp/${IMG_NAME}"

    if [[ -f "$image_path" ]]; then
        msg_ok "La imagen cloud-init ya existe"

        return
    fi

    msg_info "Descargando imagen cloud-init"

    wget -q --show-progress "$IMG_URL" -O "$image_path"

    msg_ok "Imagen descargada correctamente"
}

template_exists() {
    qm status "$TEMPLATE_VMID" >/dev/null 2>&1
}

create_template_vm() {
    CURRENT_STAGE="template_vm"

    if template_exists; then
        msg_warn "La plantilla VMID ${TEMPLATE_VMID} ya existe"

        return
    fi

    msg_info "Creando VM base para Cloud-Init"

    qm create "$TEMPLATE_VMID" \
        --name "$TEMPLATE_VM_NAME" \
        --memory "$TEMPLATE_MEMORY" \
        --cores "$TEMPLATE_CORES" \
        --net0 "virtio,bridge=${TEMPLATE_BRIDGE}"

    msg_ok "VM creada correctamente"
}

import_template_disk() {
    CURRENT_STAGE="disk_import"

    local image_path="/tmp/${IMG_NAME}"
    local import_log

    import_log=$(mktemp)

    msg_info "Importando disco Cloud-Init"

    qm importdisk \
        "$TEMPLATE_VMID" \
        "$image_path" \
        "$TEMPLATE_STORAGE" \
        2>&1 | tee "$import_log"

    TEMPLATE_DISK_PATH=$(qm config "$TEMPLATE_VMID" | \
        awk -F': ' '/^unused[0-9]+:/ {print $2; exit}')

    rm -f "$import_log"

    if [[ -z "${TEMPLATE_DISK_PATH:-}" ]]; then
        msg_error "No se pudo detectar el disco importado"

        exit 1
    fi

    msg_ok "Disco importado correctamente"
}

configure_template_hardware() {
    CURRENT_STAGE="hardware"

    msg_info "Configurando hardware de la VM"

    qm set "$TEMPLATE_VMID" \
        --scsihw virtio-scsi-pci \
        --scsi0 "$TEMPLATE_DISK_PATH"

    qm set "$TEMPLATE_VMID" \
        --ide2 "${TEMPLATE_STORAGE}:cloudinit"

    qm set "$TEMPLATE_VMID" \
        --boot c \
        --bootdisk scsi0

    qm set "$TEMPLATE_VMID" \
        --serial0 socket \
        --vga serial0

    qm disk resize \
        "$TEMPLATE_VMID" \
        scsi0 \
        "$TEMPLATE_DISK_SIZE"

    qm set "$TEMPLATE_VMID" \
        --machine q35

    qm set "$TEMPLATE_VMID" \
        --agent enabled=1

    msg_ok "Hardware configurado correctamente"
}

configure_cloudinit() {
    CURRENT_STAGE="cloudinit"

    msg_info "Configurando Cloud-Init"

    qm set "$TEMPLATE_VMID" \
        --ciuser "$CI_USER"

    qm set "$TEMPLATE_VMID" \
        --sshkeys "$SSH_PUBLIC_KEY_PATH"

    qm set "$TEMPLATE_VMID" \
        --ipconfig0 ip=dhcp

    if [[ "$CI_PASSWORD_ENABLED" == "true" ]]; then
        qm set "$TEMPLATE_VMID" \
            --cipassword "$CI_PASSWORD"

        msg_ok "Autenticación por contraseña habilitada"
    fi

    msg_ok "Cloud-Init configurado correctamente"
}

create_cloudinit_user_data() {
    CURRENT_STAGE="cloudinit_userdata"

    local snippets_dir="/var/lib/vz/snippets"
    local user_data_path="${snippets_dir}/${TEMPLATE_VM_NAME}-user-data.yaml"

    msg_info "Creando configuración Cloud-Init personalizada"

    mkdir -p "$snippets_dir"

    cat > "$user_data_path" <<EOF
#cloud-config
package_update: true
packages:
  - qemu-guest-agent

runcmd:
  - systemctl enable --now qemu-guest-agent
EOF

    qm set "$TEMPLATE_VMID" \
        --cicustom "user=local:snippets/${TEMPLATE_VM_NAME}-user-data.yaml"

    msg_ok "Cloud-Init user-data configurado correctamente"
}

convert_vm_to_template() {
    CURRENT_STAGE="template_conversion"

    msg_info "Convirtiendo VM en plantilla"

    qm template "$TEMPLATE_VMID"

    msg_ok "Plantilla convertida correctamente"
}

cleanup_cloud_image() {
    local image_path="/tmp/${IMG_NAME}"

    if [[ -f "$image_path" ]]; then
        rm -f "$image_path"

        msg_ok "Imagen temporal eliminada"
    fi
}

create_cloudinit_template() {
    CURRENT_STAGE="template"

    if template_exists; then
        msg_warn "La plantilla ${TEMPLATE_VMID} ya existe"

        return
    fi

    ensure_cloud_image

    create_template_vm
    import_template_disk

    configure_template_hardware
    configure_cloudinit
    create_cloudinit_user_data

    convert_vm_to_template

    # cleanup_cloud_image

    msg_ok "Plantilla Cloud-Init creada correctamente"
}

###############################
### Proxmox API integration ###
###############################
api_group_exists() {
    pveum group list --output-format json | \
        jq -e --arg group "$API_GROUP" \
        '.[] | select(.groupid == $group)' >/dev/null
}

create_api_group() {
    CURRENT_STAGE="api_group"

    if api_group_exists; then

        msg_ok "El grupo API ya existe"

        return
    fi

    msg_info "Creando grupo API"

    pveum groupadd \
        "$API_GROUP" \
        -comment "Grupo de automatización OpenTofu"

    msg_ok "Grupo API creado correctamente"
}

api_user_exists() {
    pveum user list --output-format json | \
        jq -e --arg user "$API_USER" \
        '.[] | select(.userid == $user)' >/dev/null
}

create_api_user() {
    CURRENT_STAGE="api_user"

    if api_user_exists; then

        msg_ok "El usuario API ya existe"

        return
    fi

    msg_info "Creando usuario API"

    pveum useradd \
        "$API_USER" \
        -comment "Usuario API OpenTofu"

    pveum usermod \
        "$API_USER" \
        -group "$API_GROUP"

    msg_ok "Usuario API creado correctamente"
}

assign_api_permissions() {
    CURRENT_STAGE="api_permissions"

    msg_info "Asignando permisos API"

    pveum aclmod / \
        -group "$API_GROUP" \
        -role Administrator

    msg_ok "Permisos asignados correctamente"
}

api_token_exists() {
    pveum user token list "$API_USER" --output-format json | \
        jq -e --arg token "$API_TOKEN_NAME" \
        '.[] | select(.tokenid == $token)' >/dev/null
}

create_api_token() {
    CURRENT_STAGE="api_token"

    msg_info "Generando token API"

    if api_token_exists; then

        msg_warn "El token API ya existe, eliminando token anterior"

        pveum user token remove \
            "$API_USER" \
            "$API_TOKEN_NAME"
    fi

    local token_output

    token_output=$(pveum user token add \
        "$API_USER" \
        "$API_TOKEN_NAME" \
        --privsep 0 \
        --output-format json)

    API_TOKEN_ID=$(echo "$token_output" | jq -r '.["full-tokenid"]')
    API_TOKEN_SECRET=$(echo "$token_output" | jq -r '.value')

    if [[ -z "${API_TOKEN_ID:-}" || -z "${API_TOKEN_SECRET:-}" ]]; then
        msg_error "No se pudo generar el token API"

        exit 1
    fi

    msg_ok "Token API generado correctamente"
}

detect_management_ip() {
    CURRENT_STAGE="management_ip"

    PROXMOX_IP=$(ip -4 addr show "$TEMPLATE_BRIDGE" | \
        awk '/inet / {print $2}' | \
        cut -d/ -f1 | \
        head -1)

    if [[ -z "${PROXMOX_IP:-}" ]]; then
        msg_error "No se pudo detectar la IP de gestión"

        exit 1
    fi

    msg_ok "IP de gestión detectada: $PROXMOX_IP"
}

detect_node_name() {
    CURRENT_STAGE="node_name"

    # Obtiene el hostname del sistema de forma local
    PROXMOX_NODE=$(hostname)

    if [[ -z "${PROXMOX_NODE:-}" ]]; then
        msg_error "No se pudo detectar el nombre del nodo Proxmox"
        exit 1
    fi

    msg_ok "Nombre del nodo detectado: $PROXMOX_NODE"
}

store_api_credentials() {
    CURRENT_STAGE="api_credentials"

    msg_info "Guardando credenciales API"

    umask 077

    cat > "$API_CREDENTIALS_FILE" <<EOF
PM_API_URL="https://${PROXMOX_IP}:8006/api2/json"
PM_NODE_NAME="${PROXMOX_NODE}"
PM_API_TOKEN_ID="${API_TOKEN_ID}"
PM_API_TOKEN_SECRET="${API_TOKEN_SECRET}"
SSH_PUBLIC_KEY="${SSH_PUBLIC_KEY_CONTENT}"
EOF

    chmod 600 "$API_CREDENTIALS_FILE"

    msg_ok "Credenciales API almacenadas correctamente"
}

configure_proxmox_api_access() {
    CURRENT_STAGE="api"

    create_api_group
    create_api_user

    assign_api_permissions

    create_api_token

    detect_management_ip
    detect_node_name
    store_api_credentials

    msg_ok "Configuración API completada"
}

###############
### Network ###
###############

configure_monitoring_bridge() {
    CURRENT_STAGE="network"

    if grep -q "CHAHA MONITORING BRIDGE BEGIN" /etc/network/interfaces; then
        msg_ok "El bridge de monitoreo ya está configurado"

        return
    fi

    msg_info "Configurando bridge de monitoreo"

    cat <<EOF >> /etc/network/interfaces

# --- CHAHA MONITORING BRIDGE BEGIN ---

auto ${MONITORING_INTERFACE}
iface ${MONITORING_INTERFACE} inet manual

auto ${MONITORING_BRIDGE}
iface ${MONITORING_BRIDGE} inet manual
    bridge-ports ${MONITORING_INTERFACE}
    bridge-stp off
    bridge-fd 0

# Bridge dedicado para monitoreo IDS/NSM
# Sin direccion IP asignada

# --- CHAHA MONITORING BRIDGE END ---
EOF

    # Configuración de mirroring al bridge virtual para monitoreo IDS/NSM
    tc qdisc add dev ${MONITORING_BRIDGE} ingress
    tc filter add dev ${MONITORING_BRIDGE} ingress \
        matchall \
        action mirred egress mirror dev ${MONITORING_BRIDGE}

    ifreload -a || true

    msg_ok "Bridge de monitoreo configurado correctamente"
}

enable_monitoring_promiscuous_mode() {
    CURRENT_STAGE="promiscuous_mode"

    msg_info "Habilitando modo promiscuo"

    if ip link set "$MONITORING_INTERFACE" promisc on; then
        msg_ok "Modo promiscuo habilitado"
    else
        msg_warn "No se pudo habilitar modo promiscuo"
    fi
}

################
### VM Clone ###
################

master_vm_exists() {
    qm status "$MASTER_VMID" >/dev/null 2>&1
}

create_iac_master_vm() {
    CURRENT_STAGE="iac_vm"

    if master_vm_exists; then
        msg_warn "La VM Master ya existe"

        return
    fi

    msg_info "Clonando VM Master para IaC"

    qm clone \
        "$TEMPLATE_VMID" \
        "$MASTER_VMID" \
        --name "$MASTER_VM_NAME" \
        --full

    msg_ok "VM Master creada correctamente"
}

print_summary() {
    echo ""

    echo "================================================="
    echo "         Configuración completada"
    echo "================================================="
    echo ""
    echo "Plantilla Cloud-Init"
    echo "  VMID:        ${TEMPLATE_VMID}"
    echo "  Nombre:      ${TEMPLATE_VM_NAME}"
    echo "  Disco:       ${TEMPLATE_DISK_SIZE}"
    echo ""
    echo "VM IaC"
    echo "  VMID:        ${MASTER_VMID}"
    echo "  Nombre:      ${MASTER_VM_NAME}"
    echo "  Usuario:     ${CI_USER}"
    echo "  Contraseña:  ${CI_PASSWORD}"
    echo ""
    echo "SSH"
    echo "  Llave privada: ${SSH_PRIVATE_KEY_PATH}"
    echo "  Llave pública: ${SSH_PUBLIC_KEY_PATH}"
    echo ""
    echo "Proxmox API"
    echo "  URL:         https://${PROXMOX_IP}:8006"
    echo "  Usuario:     ${API_USER}"
    echo "  Archivo:     ${API_CREDENTIALS_FILE}"
    echo ""
    echo "================================================="
}

main "$@"