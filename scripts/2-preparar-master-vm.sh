#!/usr/bin/env bash

set -euo pipefail
shopt -s inherit_errexit

CURRENT_STAGE="startup"

trap 'msg_error "Falló en etapa: ${CURRENT_STAGE}"' ERR

########################
### Global Variables ###
########################

readonly REPO_URL="https://github.com/0beIix/Chaha.git"
readonly REPO_PATH="/root/Chaha"

readonly API_CREDENTIALS_FILE="/root/.proxmox-api"

readonly TFVARS_PATH="$REPO_PATH/tofu/secrets.tfvars"

readonly PROXMOX_USER="root"
readonly PROXMOX_HOST="192.168.100.50"
readonly PROXMOX_API_FILE="/root/.proxmox-api"

########################
### No editar debajo ###
########################

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

    install_required_packages

    install_opentofu
    install_ansible

    setup_repository

    retrieve_proxmox_credentials
    load_proxmox_credentials

    generate_tfvars

    cleanup_sensitive_files
}

########################
### Dependency check ###
########################

check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        msg_error "Este script debe ejecutarse como root"

        exit 1
    fi
}

readonly REQUIRED_PACKAGES=(
    curl
    wget
    git
    jq
    software-properties-common
    tree
)

install_required_packages() {
    CURRENT_STAGE="packages"

    msg_info "Instalando dependencias básicas"

    apt-get update -qq

    apt-get install -y "${REQUIRED_PACKAGES[@]}"

    msg_ok "Dependencias instaladas correctamente"
}

################
### OpenTofu ###
################

install_opentofu() {
    CURRENT_STAGE="opentofu"

    if command -v tofu >/dev/null 2>&1; then
        msg_ok "OpenTofu ya está instalado"

        return
    fi

    msg_info "Instalando OpenTofu"

    local installer="/tmp/install-opentofu.sh"

    curl --proto '=https' \
        --tlsv1.2 \
        -fsSL \
        https://get.opentofu.org/install-opentofu.sh \
        -o "$installer"

    chmod +x "$installer"

    "$installer" --install-method deb

    rm -f "$installer"

    msg_ok "OpenTofu instalado correctamente"
}
###############
### Ansible ###
###############

install_ansible() {
    CURRENT_STAGE="ansible"

    if command -v ansible >/dev/null 2>&1; then
        msg_ok "Ansible ya está instalado"

        return
    fi

    msg_info "Instalando Ansible"

    add-apt-repository --yes --update ppa:ansible/ansible

    apt-get install -y ansible

    msg_ok "Ansible instalado correctamente"
}

########################
### Repository Setup ###
########################

setup_repository() {
    CURRENT_STAGE="repository"

    if [[ -d "$REPO_PATH/.git" ]]; then
        msg_info "Actualizando repositorio Chaha"

        git -C "$REPO_PATH" pull

        msg_ok "Repositorio actualizado"

        return
    fi

    msg_info "Clonando repositorio Chaha"

    git clone "$REPO_URL" "$REPO_PATH"

    msg_ok "Repositorio clonado correctamente"
}

#######################
### Proxmox Secrets ###
#######################

retrieve_proxmox_credentials() {
    CURRENT_STAGE="credentials"

    if [[ -f "$TFVARS_PATH" ]]; then
        msg_ok "El archivo secrets.tfvars ya existe"

        return
    fi

    msg_info "Obteniendo credenciales desde Proxmox"

    scp \
        "${PROXMOX_USER}@${PROXMOX_HOST}:${PROXMOX_API_FILE}" \
        "$API_CREDENTIALS_FILE"

    chmod 600 "$API_CREDENTIALS_FILE"

    msg_ok "Credenciales obtenidas correctamente"
}

read_config_value() {
    local key="$1"

    grep "^${key}=" "$API_CREDENTIALS_FILE" | cut -d'"' -f2
}

load_proxmox_credentials() {
    CURRENT_STAGE="credentials_load"

    if [[ ! -f "$API_CREDENTIALS_FILE" ]]; then
        msg_error "No existe el archivo de credenciales API"

        exit 1
    fi

    msg_info "Cargando credenciales API"

    PM_API_URL=$(read_config_value "PM_API_URL")
    PM_API_TOKEN_ID=$(read_config_value "PM_API_TOKEN_ID")
    PM_API_TOKEN_SECRET=$(read_config_value "PM_API_TOKEN_SECRET")
    SSH_PUBLIC_KEY=$(read_config_value "SSH_PUBLIC_KEY")

    if [[ -z "${PM_API_URL:-}" || \
          -z "${PM_API_TOKEN_ID:-}" || \
          -z "${PM_API_TOKEN_SECRET:-}" ]]; then

        msg_error "No se pudieron cargar las credenciales API"

        exit 1
    fi

    msg_ok "Credenciales API cargadas correctamente"
}

######################
### secrets.tfvars ###
######################

generate_tfvars() {
    CURRENT_STAGE="tfvars"

    msg_info "Generando secrets.tfvars"

    cat > "$TFVARS_PATH" <<EOF
proxmox_api_token = "${PM_API_TOKEN_ID}=${PM_API_TOKEN_SECRET}"
proxmox_endpoint  = "${PM_API_URL}"
ssh_public_key   = "${SSH_PUBLIC_KEY}"
EOF

    chmod 600 "$TFVARS_PATH"

    msg_ok "Archivo secrets.tfvars generado correctamente"
}

cleanup_sensitive_files() {
    CURRENT_STAGE="cleanup"

    msg_info "Limpiando archivos sensibles"

    rm -f "$API_CREDENTIALS_FILE"

    history -c || true

    msg_ok "Archivos sensibles eliminados"
}

main "$@"