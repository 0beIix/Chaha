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

############################
### Setup de Repositorio ###
############################

### 4. CLONAR EL REPOSITORIO CHAHA
echo "[*] Clonando el repositorio Chaha desde GitHub…"
rm -rf ~/Chaha
git clone https://github.com/0beIix/Chaha.git ~/Chaha

### 5. CONFIGURAR CREDENCIALES AUTOMÁTICAMENTE
read -p "Ingrese la IP de Proxmox: " PROXMOX_HOST

# CORRECCIÓN SCP: Forzamos que el destino sea el archivo local
echo "[*] Obteniendo credenciales desde Proxmox..."
scp root@${PROXMOX_HOST}:/root/.proxmox-api "$HOME/.proxmox-api"

# Cargar variables (asegúrate de que el archivo en Proxmox use 'export PM_...')
source "$HOME/.proxmox-api"

echo "[*] Generando secrets.tfvars…"
# CORRECCIÓN: El formato del token para el provider bpg suele ser "ID=SECRET" 
# pero asegúrate de que coincida con lo que espera tu provider.
cat <<EOF > ~/Chaha/tofu/secrets.tfvars
proxmox_api_token = "${PM_API_TOKEN_ID}=${PM_API_TOKEN_SECRET}"
proxmox_endpoint  = "${PM_API_URL}"
ssh_public_key    = "${SSH_PUBLIC_KEY}"
EOF

##############################
### LIMPIEZA DE SEGURIDAD  ###
##############################

echo "[*] Limpiando archivos temporales de seguridad..."

# Borramos el archivo de variables descargado para no dejar credenciales en texto plano en el home
if [ -f "$HOME/.proxmox-api" ]; then
    rm "$HOME/.proxmox-api"
    msg_ok "Archivo .proxmox-api eliminado localmente."
fi

# Opcional: Borrar el historial de bash para que la IP y comandos no queden registrados
history -c

echo -e "\n[*] Entorno preparado exitosamente."
echo "-------------------------------------------------------"
echo " Ubicación: ~/Chaha/tofu"
echo " 1. cd ~/Chaha/tofu"
echo " 2. tofu init"
echo " 3. tofu apply -var-file=secrets.tfvars"
echo "-------------------------------------------------------"