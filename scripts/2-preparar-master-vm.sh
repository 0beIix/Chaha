#!/bin/bash
set -e

#############################
### INSTALAR DEPENDENCIAS ###
#############################

echo "[*] Instalando dependencias básicas…"
sudo apt update && sudo apt install -y curl wget git jq software-properties-common

### 1. INSTALAR OPEN TOFU
echo "[*] Instalando OpenTofu…"
curl --proto '=https' --tlsv1.2 -fsSL https://get.opentofu.org/install-opentofu.sh -o install-opentofu.sh
chmod +x install-opentofu.sh
./install-opentofu.sh --install-method deb
rm -f install-opentofu.sh

### 2. INSTALAR ANSIBLE ###
echo "[*] Instalando Ansible…"
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt install -y ansible tree

### 3. DETECTAR ÚLTIMA VERSIÓN DEL PROVEEDOR
echo "[*] Buscando la última versión de bpg/proxmox..."
LATEST_VERSION=$(curl -s https://api.github.com/repos/bpg/terraform-provider-proxmox/releases/latest | jq -r .tag_name | sed 's/v//')
echo "[*] Versión detectada: $LATEST_VERSION"

############################
### Setup de Repositorio ###
############################

### 4. CLONAR EL REPOSITORIO CHAHA
echo "[*] Clonando el repositorio Chaha desde GitHub…"
rm -rf ~/Chaha # Limpiar si ya existe
git clone https://github.com/0beIix/Chaha.git ~/Chaha
cd ~/Chaha/tofu

### 5. CONFIGURAR CREDENCIALES AUTOMÁTICAMENTE
read -p "Ingrese la IP de Proxmox: " PROXMOX_HOST
# Traemos el archivo .proxmox-api generado por el primer script
scp root@${PROXMOX_HOST}:/root/.proxmox-api ~/.proxmox-api
source ~/.proxmox-api

echo "[*] Generando secrets.tfvars…"
cat <<EOF > ~/Chaha/tofu/secrets.tfvars
proxmox_api_token = "$PM_API_TOKEN_ID=$PM_API_TOKEN_SECRET"
proxmox_endpoint  = "$PM_API_URL"
ssh_public_key    = "$(cat ~/.ssh/id_ed25519.pub)"
EOF

echo "[*] Entorno preparado. Ya puedes ejecutar:"
echo " 1. 'tofu init' para inicializar"
echo " 2. 'tofu plan -var-file=secrets.tfvars' para planificar"
echo " 3. 'tofu apply -var-file=secrets.tfvars' para aplicar"