## Mise en place d'une infrastructure vmWare de type 'Nested Virtualization'
Les valeurs entre crochets sont les valeurs utilisées lors de mon installation.
La machine servant à l'installation sera appelé poste d'installation.
Il est conseillé de connecter en ethernet le poste d'installation sur le switch du cluster NUC.
Mon poste d'installation est un ubuntu-18.04.3-desktop-amd64.

### Fichiers nécessaires dans le répertoire 'Files'
* Hyperviseur ESXi [VMware-VMvisor-Installer-6.5.0.update02-8294253.x86_64.iso]
* vCenter / vSphere [VMware-VCSA-all-6.7.0-10244745.iso]
* Fichier de configuration du vCenter [embedded_vCSA_on_ESXi.json] - Ne pas renommer
* OVF d'un vESX [./vesx-ovf/vESX1/vESX1.ovf] - Ne pas renommer

### Configuration du switch
* La connexion Internet est configurée sur l'entrée WAN du switch.
* Il est conseillé de brancher le poste d'installation sur le switch pour accélérer l'installation du cluster.
* Adresses IP statiques pour les NUC
  * IP dynamiques : 42.42.1.[90-120]
  * Nuc1  42.42.1.11 b8:ae:ed:7c:3a:87
  * Nuc2  42.42.1.12 f4:4d:30:6a:8c:68
  * Nuc3  42.42.1.13 b8:ae:ed:7d:9e:80
  * Nuc4  42.42.1.14 f4:4d:30:69:68:2c
  * vesx1-30 42.42.1.[21-50] 00:50:56:a1:00:[01-50]
  * **NOTE** : le dernier nombre des adresses MAC des vESXi ne contient pas de caractère hexadécimal
```text
================
= Nuc3 == Nuc4 =
================
= Nuc1 == Nuc2 =
================
=    Switch    =
================
= Alimentation =
================
```

### Installation des ESXi
* Créer une clé USB d'installation avec Rufus (sous Windows) à partir d'une image ISO VMvisor [VMware-VMvisor-Installer-6.5.0.update02-8294253.x86_64.iso]
* Installer les ESXi sur tous les NUCs disponibles
  * mot de passe root : (voir configuration.json)
  * **NOTE** : Ne pas retirer la prise de l'écran lors de l'installation car on doit redémarrer le NUC pour retrouver l'affichage (même après installation de l'ESXi)
* **ATTENTION** : Pour la création d'une VM via l'interface Web de l'ESXi, désactiver les effets graphiques peut corriger les problèmes d'affichage des propriétés de la VM :
  * Menu "root@192.x.x.x" > Settings > Décocher "Enable visual effects"

### Installation du vCenter
* Choisir l'ESXi qui hébergera le vCenter et noter son adresse IP et le nom de son datastore
* Complèter le fichier de configuration *embedded_vCSA_on_ESXi.json* :
  * Noter l'IP de l'ESXi dans le champs esxi/hostname
  * Noter le mot de passe root dans le champs esxi/password
  * Noter le nom du datastore dans le champs esxi/datastore
* Télécharger l'ISO du vCenter Service Appliance [VMware-VCSA-all-6.7.0-10244745.iso]
* Sous Ubuntu, installer la librairie libgconf
  * sudo apt install libgconf2-4
* Monter l'image sur le poste d'installation (Windows, Linux ou Mac) [Ubuntu 64 bits] et lancer l'installeur
   * mkdir /tmp/vcsa
   * sudo mount -o loop VMware-VCSA-all-6.7.0-10244745.iso /tmp/vcsa
   * cd /tmp/vcsa/vcsa-cli-installer/lin64/
* **ATTENTION**: Dans le fichier *embedded_vCSA_on_ESXi.json* tous les  mots de passe sont en clair !
  * Modifier les mots de passe du le fichier *embedded_vCSA_on_ESXi.json* et les reporter dans le fichier *configuration.json*
  * ./vcsa-deploy install --accept-eula --no-ssl-certificate-verification ./Files/embedded_vCSA_on_ESXi.json
  * **NOTE** : En cas de bug de l'installer graphique, effacer le répertoire ~/.config/Installer

### Installation de PowerCLI sur le poste d'installation
* PowerShell
```
curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
curl https://packages.microsoft.com/config/ubuntu/16.04/prod.list | sudo tee /etc/apt/sources.list.d/microsoft.list
sudo apt-get update
sudo apt-get install -y powershell
```
* PowerCLI
```
Install-Module -Name VMware.PowerCLI -Scope CurrentUser
Update-Module -Name VMware.PowerCLI
```

### Configuration de l'infrastructure
* Start the powerShell shell : `pwsh`
* Run the deployment script : `./deploy.ps1`

### Création de l'OVF des ESXi virtuels (vESX)
* Créer une nouvelle machine virtuelle
  * Guest OS Family: Linux, Guest OS Version: Other Linux 64 bit
  * Customize hardware
    * CPU: Number: 2, tick both "Expose hardware assisted virtualization to the guest OS" and "Enable virtualized CPU performance counters"
    * Memory: 4 GB
    * New Hard Disk: 200 GB, Disk Provisioning: Thin Provisioning
    * New CD/DVD drive: Datastore ISO File, tick "Connect"
* Démarrer la machine virtuelle et installer l'ESXi
  * "Power On"
  * Ne pas oublier le mot de passe
* Retirer l'ISO de la machine virtuelle
  * Edit Settings > CD/DVD Drive > Client Device
* Redémarrer la machine virtuelle
* Activer l'accès SSH sur l'ESXi fraîchement installé (vESXi)
  * Troubleshooting Options > Enable SSH
* (Optionnel) Copier la clé SSH du poste d'installation
  * `cat ~/.ssh/id_rsa.pub | ssh root@IPvESXi 'cat >> /etc/ssh/keys-root/authorized_keys'`
* Suppression des UUID du vESXi
  * Se connecter via SSH sur le vESXi et entrer les commandes suivantes
```text
esxcli system settings advanced set -o /Net/FollowHardwareMac -i 1
sed -i 's#/system/uuid.*##' /etc/vmware/esx.conf
/sbin/auto-backup.sh
poweroff
```
* Création de l'OVF à partir d'un shell PowerShell (la connexion au vCenter doit être exécutée au préalable *vcenter-connect.ps1*)
  * `Get-VM -Name "vesx1" | Export-VApp -Destination vesx-ovf -Force`

### Arrêt automatique du cluster
* Configuration des accès SSH des ESXi
  * Activer l'accès SSH via l'interface physique de management
    * F2 > Troubleshooting Options > Enable SSH
  * **ATTENTION** : l'activation SSH via l'interface web n'est pas permanente et sera perdue après le redémarrage
* Copier la clé SSH du poste d'installation sur les ESXi dans le bon fichier
  * `cat ~/.ssh/id_rsa.pub | ssh root@192.x.x.x 'cat >> /etc/ssh/keys-root/authorized_keys'`
* Utiliser le script `shutdown.sh` pour éteindre le cluster
  * Extinction de toutes les VM
  * Extinction des ESXi physiques
  * Ne pas oublier d'éteindre le switch ;)

### Création d'utilisateurs ayant accès à un seul centre de données
* À partir de l'interface du client vSphere, créer un nouvel utilisateur
  * Menu > Administration
  * Single Sign On > Users and Groups
  * Domain: vsphere.local > Add user
  * Username: adminG1, Password: adminG1$$
* Attribuer l'utilisateur à un centre de données
  * Menu > Home > Hosts and clusters
  * Select the datacenter > Permissions
  * Add > User: vsphere.local, search for "adminG1", Role: Administrator, tick "Propagate to children"

### Mise en place du vSan via l'interface graphique du vCenter
* Les 3 vESXi sont déjà dans un datacenter
* Créer un cluster dans le datacenter (Ne pas activer vSan !)
* Déplacer les vESXi dans le cluster
* Activer le vSan sur les vESXi
  * Configure > Networking / VMKernel Adapters > Edit > Cocher vSan
* Activer le vSan du cluter
  * Configure > vSan / Services > Enable vSan
  * Laisser les valeurs par défaut (normalement, les disques durs des vESXi sont détectés)

### TP High Availability
#### Panne sur la VM (Ne fonctionne pas)
* Activer le vSphere Availability sur le cluster souhaité
  * Configure > vSphere Availability > Edit
  * VM Monitoring > cocher "VM Monitoring Only", "Failure Interval": 10, "Minimum uptime": 20
* Installation de iptables sur yVM
  * root / VMware1!
  * `tce-load -wi iptables`
* À partir d'une machine externe, on lance un ping sur l'IP de la VM
  * `ping -W 3 -i 2 -O 192.168.x.x`
* Isolation de la VM
  * `ssh root@192.168.x.x "sudo iptables -P INPUT DROP && sudo iptables -P OUTPUT DROP && sudo iptables -P FORWARD DROP"`
  * `Ctrl-C` pour fermer la connexion SSH

#### Panne sur le serveur
* Activer vMotion sur tous les serveurs du cluster
  * Configure > Networking / VMKernel Adapters > Edit
* Démarrer une VM "yVM" sur le serveur A (vESXi)
* Trouver la VM correspondant au vESXi et déconnecter la carte réseau
  * Summary > Edit Settings > Décocher "Connected" du "Network adapter 1"
* Attendre le déplacement de la VM "yVM"

### TP DRS
* Activer vMotion sur les vESXi
  * Configure > Networking / VMKernel Adapters > Edit
* Activer vSphere DRS sur le cluster
  * Configure > vSphere DRS > Edit
* Démarrer 3 VM sur un des vESXi
* Installer stress dans les VM
```
scp stress.tcz tc@192.168.x.x:
ssh tc@192.168.x.x
tce-load -i stress.tcz
```
* Générer une charge CPU avec stress sur 2 des VM
  * `stress -c 1`
* Attendre que la migration soit effectuée

### Resources
* Clone vESXi: https://www.virtuallyghetto.com/2013/12/how-to-properly-clone-nested-esxi-vm.html
* Promiscuous mode: https://isc.sans.edu/forums/diary/Running+Snort+on+VMWare+ESXi/15899/
* vSan Configuration: https://www.vladan.fr/vmware-vsan-configuration/
