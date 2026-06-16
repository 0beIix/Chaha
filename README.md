# Chaha
Inspirado en el Chahã del Chaco, este sistema actúa como centinela digital: monitorea la red en tiempo real, detecta anomalías y emite alertas inmediatas ante intrusos, permitiendo una respuesta rápida y coordinada.

### Estructura del proyecto
```
chaha
├── ansible/                # Configuración de software en las VMs
│   ├── group_vars/         # Variables compartidas por grupos
│   │   └── sensor_nodes.yml
│   ├── inventory/
│   │   └── hosts.ini       # IPs y acceso SSH de los nodos
│   ├── roles/              # Lógica de instalación (Suricata, Zeek, Wazuh)
│   │   ├── suricata
│   │   ├── wazuh-agent
│   │   ├── wazuh-server
│   │   └── zeek
│   └── site.yml            # Playbook maestro de Ansible
├── scripts/                # Scripts de preparación inicial
│   ├── 1-preparar-proxmox.sh
│   └── 2-preparar-master-vm.sh
└── tofu/                   # Orquestación de infraestructura (IaC)
    ├── chaha.auto.tfvars   # Definición de hardware (vCPU, RAM, Disco)
    ├── main.tf             # Despliegue de módulos
    ├── modules/            # Blueprints de las VMs
    │   ├── sensor_node
    │   └── wazuh_node
    ├── providers.tf
    ├── secrets.tfvars      # Credenciales (Ignorado por Git)
    └── variables.tf
```
### Requicitos iniciales
1. Servidor físico con Proxmox instalado y al menos dos puertos de red.
2. Switch gestionable para configurar un puerto de monitoreo (Port Mirror/SPAN).
3. Acceso a internet para descarga de paquetes y reglas.

### Operativa Breve
1. Preparación del Host (Proxmox)

> [!IMPORTANT]
> Ejecuta PVE Post Install Script después de instalar para configurar repositorios, quitar el 'nag' y actualizar el sistema, generalmente responder todo con 'y'.

``` bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/tools/pve/post-pve-install.sh)"
```

Ejecutar el setup script en el shell de Proxmox. Este paso deja el hipervisor listo para recibir órdenes de OpenTofu.

> [!IMPORTANT]
> Podes pero no necesitas editar las variables de la sección "Variables Editables" dentro del script antes de ejecutar.    
    
``` bash
curl -sSLO https://raw.githubusercontent.com/0beIix/Chaha/main/scripts/1-preparar-proxmox.sh
chmod +x 1-preparar-proxmox.sh
./1-preparar-proxmox.sh
```

- Genera llaves SSH y configura accesos.
- Descarga la imagen Cloud-Init y crea la plantilla base.
- Crea el usuario API terraform@pve con permisos de administrador.
- Configura el bridge vmbr1 (modo promiscuo) para sniffing.
- Despliega la VM Maestra desde donde se gestionará el resto.

2. Preparación de la VM Maestra

``` bash
curl -sSLO https://raw.githubusercontent.com/0beIix/Chaha/main/scripts/2-preparar-master-vm.sh
chmod +x 2-preparar-master-vm.sh
./2-preparar-master-vm.sh
```

- Dentro de la nueva VM creada, ejecutar 2-preparar-master-vm.sh:
- Instala OpenTofu y Ansible.
- Clona este repositorio para iniciar la gestión.

3. Despliegue de Infraestructura (OpenTofu)

Configurar las dimensiones en chaha.auto.tfvars e IPs.

```bash
cd ~/chaha/tofu
tofu init
tofu plan -var-file=secrets.tfvars
tofu apply -var-file=secrets.tfvars
```
4. Configuración del Stack (Ansible)

Una vez creadas las VMs, desplegar el software de seguridad:

```bash
cd ~/chaha/ansible
# Primero probamos conexión
ansible -i inventory/hosts.ini all -m ping

# Ejecutar instalación
ansible-playbook -i inventory/hosts.ini site.yml
```
