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
1. Tener un servidor fisico con dos puertos de red y proxmox instalado
2. Tener un switch gestionable para crear un puerto de monitoreo (port mirror)

### Operativa Breve
1. En el servidor de Proxmox ejecutar el script '1-preparar-proxmox.sh'
    > [!Info] Importante
    >  Definir las variables en la primera sección antes de ejecutar
    1. Crea keys para SSH
    2. Descarga dependencias
    3. Descarga Imagen CLOUD-INIT y crea un template
    4. Crea el usuario necesario y API key y configura permisos 
    5. Configura la red (VMBR1)
    6. Crea la VM maestra en donde se sigue
2. En la nueva VM maestra ejecutar 2-preparar-master-vm.sh
    1. Instala dependencias necesarias
    2. Instala OpenTofu y Ansible
    3. Clona este repositorio
3. Entrar en el directorio 'tofu'
> [!Info] Configurar Variables
> Configurar variables en chaha.auto.tfvars
Para ejecutar y crear las VMs ejecutar
```bash
cd ~/chaha/tofu
tofu init
tofu plan -var-file=secrets.tfvars
tofu apply -var-file=secrets.tfvars
```
4. Entrar en el directorio 'ansible'
```bash
cd ~/chaha/ansible
# Primero probamos conexión
ansible -i inventory/hosts.ini all -m ping

# Ejecutar instalación
ansible-playbook -i inventory/hosts.ini site.yml
```
