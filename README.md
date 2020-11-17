## Mise en place d'une infrastructure vmWare de type 'Nested Virtualization'
Les valeurs entre crochets sont les valeurs utilisées lors de mon installation.
La machine servant à l'installation sera appelé poste d'installation.
Il est conseillé de connecter en ethernet le poste d'installation sur le switch du cluster NUC.
Mon poste d'installation est un ubuntu-18.04.3-desktop-amd64.
Pour installer l'infrastructure nécessaire aux TP, les grandes étapes sont :
1. Installation des ESXi sur les NUC à partir d'une clé USB et de  l'ISO *VMware-VMvisor-Installer*.
La clé USB est créée avec Rufus.
2. Installation du vCenter en ligne de commande à partir du script *vcsa-deploy* disponible dans l'ISO *VMware-VCSA-all*
3. Écriture des adresses MAC des vESXi dans le serveur DHCP. Les adresses MAC commencent par la propriété *dhcp_mac_addr* de la section *architecture* suivi du numéro du vESXi en hexadécimal. Par exemple, avec *01:02:03:04:05:* en *dhcp_mac_addr*, l'adresse MAC du vesx012 sera *01:02:03:04:05:0C*.
4. Deploiement de l'infrastructure virtuelle utilisée pour les TP à l'aide du script *deploy.ps1*
5. Création d'utilisateurs supplémentaires à partir du vCenter via l'interface web
6. Attribution des permissions aux nouveaux utilisateurs avec le script *set-permissions.ps1*
7. Réalisations des TP par les étudiants

### Liste des fichiers téléchargés pour l'installation de l'infrastructure
* Hyperviseur ESXi : *VMware-VMvisor-Installer-6.5.0.update02-8294253.x86_64.iso* (Pour l'utilisation NSX, il faut un ESXi 6.7.0)
* vCenter / vSphere : *VMware-VCSA-all-6.7.0-10244745.iso*
* Fichier de configuration du vCenter : *embedded_vCSA_on_ESXi.json*
* Distribution Linux ultra-légère : *tinycore.iso* - version 10
* Paquet pour l'installation de l'utilitaire *stress* sur tinycore : *stress.tcz*

### Liste des fichiers disponibles
* *configuration.json* : Fichier de configuration
* *copy-ssh-key.sh* : Script bash pour copier une clé SSH sur un ESXi (root)
* *delete-infra.ps1* : Script PowerShell supprimant tous les éléments créés par le script *deploy.ps1*
* *delete-student-vms.ps1* : Script PowerShell effaçant les VM n'étant pas des vESXi
* *deploy.ps1* : Script PowerShell déployant l'infrastructure virtualisée via le vCenter
* *dhcp-generator.sh* : Script bash pour générer la configuration IP des vESXi du serveur DHCP
* *header.ps1* : Script PowerShell effectuant la connexion au vCenter
* *set-permissions.ps1* : Script PowerShell configurant les droits des nouveaux utilisateurs pour l'exécution des TP
* *shutdown-vms.ps1* : Script PowerShell pour éteindre le cluster sauf le vCenter
* *start.sh* : Script bash pour démarrer le cluster une fois les NUC allumés
* *stop.sh* : Script bash pour éteindre la totalité du cluster (sauf le switch)
* *tp-drs.txt* : TP sur vSphere DRS
* *tp-ha.txt* : TP sur vSphere HA
* *tp-vcenter* : TP sur les bases du vCenter

### Configuration du Switch en mode LAN Only
* Se connecter à l'interface d'administration du switch
* Advanced Settings > VLAN
* Décocher le "WAN Port" du VLAN 2 > Ok
* Cocher le "WAN Port" du VLAN 1 > Ok
* Cliquer sur "Save" et attendre le redémarrage du switch

### Installation et déploiement de l'infrastructure
#### Installation des ESXi
* Créer une clé USB d'installation avec Rufus (sous Windows) à partir d'une
image ISO VMvisor [VMware-VMvisor-Installer-6.5.0.update02-8294253.x86_64.iso]
* Installer les ESXi sur tous les NUCs disponibles
  * mot de passe root : (voir configuration.json)
  * **NOTE** : Ne pas retirer la prise de l'écran lors de l'installation car on doit redémarrer le NUC pour récupérer
  l'affichage (même après installation de l'ESXi)
* **ATTENTION** : Pour la création d'une VM via l'interface Web de l'ESXi, désactiver les effets graphiques peut
corriger les problèmes d'affichage, par exemple, des propriétés de la VM :
  * Menu "root@192.x.x.x" > Settings > Décocher "Enable visual effects"

#### Installation du vCenter
* Télécharger l'ISO du vCenter Service Appliance [VMware-VCSA-all-6.7.0-10244745.iso]
* Choisir l'ESXi qui hébergera le vCenter et noter son adresse IP et le nom de son datastore
* Complèter le fichier de configuration *embedded_vCSA_on_ESXi.json* :
  * Noter l'IP de l'ESXi dans le champs esxi/hostname
  * Noter le mot de passe root dans le champs esxi/password
  * Noter le nom du datastore dans le champs esxi/datastore
* Modifier les mots de passe du fichier *embedded_vCSA_on_ESXi.json* et les reporter dans le fichier *configuration.json*
* **ATTENTION**: Dans les fichiers *embedded_vCSA_on_ESXi.json* et *configuration.json* tous les mots de passe sont en clair !
* Monter l'image sur le poste d'installation (Windows, Linux ou Mac) et lancer l'installeur en précisant le chemin vers le fichier *embedded_vCSA_on_ESXi.json*
* **ATTENTION** Pour installer le vCenter, l'ESXi doit avoir accès à Internet.
##### Sous Linux (Ubuntu 18.04)
```
mkdir /tmp/vcsa
sudo mount -o loop VMware-VCSA-all-6.7.0-10244745.iso /tmp/vcsa
cd /tmp/vcsa/vcsa-cli-installer/lin64/
./vcsa-deploy install --accept-eula --no-ssl-certificate-verification ./Files/embedded_vCSA_on_ESXi.json
```
##### Sous MacOS
```
hdiutil mount vmware-VCSA-all-6.7.0-10244745.iso
cd /Volumes/VMware\ VCSA/vcsa-cli-installer/mac/
./vcsa-deploy install --accept-eula --no-ssl-certificate-verification ./Files/embedded_vCSA_on_ESXi.json
```

##### Notes sur l'installateur graphique
* Sous Ubuntu, installer la librairie libgconf
  * `sudo apt install libgconf2-4`
* En cas de bug de l'installeur graphique, effacer le répertoire ~/.config/Installer

#### Déploiement de l'infrastructure virtuelle
##### Installation de PowerCLI sur le poste d'installation
* PowerShell
##### Sous Linux (Ubuntu 18.04)
```
# Add the Microsoft repository
curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
curl https://packages.microsoft.com/config/ubuntu/16.04/prod.list | sudo tee /etc/apt/sources.list.d/microsoft.list
# Add the old Ubuntu repository to install the library libicu55
sudo add-apt-repository "deb http://security.ubuntu.com/ubuntu xenial-security main"
# Install PowerShell
sudo apt-get update
sudo apt-get install -y powershell
```
##### Sous MacOS
```
brew cask install powershell
```
* PowerCLI
```
Install-Module -Name VMware.PowerCLI -Scope CurrentUser
Update-Module -Name VMware.PowerCLI
# Do not participate to the Customer Experience Improvement Program
Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false
# Do not use SSL connections
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
```

##### Déploiement et configuration des VM vESXi
* Le fichier de configuration *configuration.json* est utilisé par le script *deploy.ps1*. Éditer le fichier de
configuration afin de vérifier les informations. Pour plus de précision sur ce fichier, se reporter à
[cette section](#le-fichier-de-configuration)
* Lancer le shell PowerShell : `pwsh`
* Lancer le script de déploiement : `./deploy.ps1`
  * Pour éviter le changement des mots de passe des vESXi, l'option `nopwd` peut être utilisée : `./deploy.ps1 nopwd`

##### Création d'utilisateurs ayant un accès restreint
* Créer un nouvel utilisateur par centre de données commençant par *new_dc_basename*, c.-à-d., les centres de données
créés pour les étudiants. Le nom des utilisateurs doivent être *user_basename* suivi du numéro de création. Par
exemple, si *user_basename* est "adminDC", les utilisateurs seront : adminDC1, adminDC2, adminDC3, adminDC4, etc.
Les valeurs *new_dc_basename* et *user_basename* sont définis dans le fichier de configuration.
* À partir de l'interface du client vSphere, créer un nouvel utilisateur
  * Menu > Administration
  * Single Sign On > Users and Groups
  * Domain: vsphere.local > Add user
  * Username: adminG1, Password: adminG1$$
* Lancer le script configurant les permissions des nouveaux utilisateurs : `./set-permissions.ps1`
* L'infrastructure est prête

### Le fichier de configuration
* **ATTENTION** Tous les comptes et mots de passe sont définis dans le fichier de configuration.
* Le fichier de configuration est un fichier JSON. L'ordre des sections n'a pas d'importance. Toutes les propriétés
doivent être présentes. Toutes les propriétés disponibles sont présentes dans le `configuration.json` fourni.

#### La section *vcenter*
* Cette section décrit les informations nécessaires à la gestion du vCenter (connexion, démarrage, arrêt).
  * *ip* : IP du vCenter
  * *host* : IP de l'ESXi hébergeant le vCenter
  * *user* : Utilisateur pour se connecter à vSphere
  * *pwd* : Mot de passe de l'utilisateur

#### La section *physical_esx*
* Cette section décrit les informations nécessaires à la gestion des ESXi ainsi que le nombre
de vESXi (ESXi installés dans des VM) hébergés par chaque ESXi (physique).
  * *ip* : IP de l'ESXi
  * *user* : Utilisateur pour se connecter à l'ESXi
  * *pwd* : Mot de passe de l'utilisateur
  * *nb_vesx* : Nombre de vESXi hébergés par l'ESXi

#### La section *virtual_esx*
* Cette section décrit les informations utilisées pour la création des VM utilisées pour installer les ESXi virtuels (vESXi). 
  * *user* : Utilisateur pour se connecter au vESXi
  * *pwd* : Nouveau mot de passe du compte root
  * *basename* : Base de nom utilisé pour créer les VM contenant les vESXi. Le nom complet est formé par
  cette base suivie d'un chiffre.
**ATTENTION**: Le mot de passe doit correspondre à la politique de sécurité de VMware :
  * Au moins 8 caractères
  * Au moins une minuscule
  * Au moins une majuscule
  * Au moins un caractère spécial
  * Moins de 20 caractères

#### La section *architecture*
* Cette section regroupe toutes les informations supplémentaires nécessaires à la création de l'infrastructure virtuelle.
  * *main_dc* : Nom du datacenter contenant les ESXi physiques (ceux décrit dans la section *physical_esx*
  * *new_dc_basename* : Début du nom des centres de données contenant les vESXi utilisés pour les exercices décrit dans les
  fichiers *tp-vcenter.txt* et *tp-ha-drs.txt*. À ce nom est concaténé le numéro de création du datacenter.
  Ce numéro est incrémenté à chaque création d'un datacenter.
  * *user_basename* : Base de nom utilisé pour créer les utilisateurs supplémentaires avec des droits restreints sur l'architecture.
  * *nb_vesx_datacenter* : Nombre de datacenter contenant des vESXi
  * *dhcp_mac_addr* : Base de nom utilisé (5 premiers nombres hexadécimaux) pour générer les adresses MAC des vESXi.
  * *dhcp_mac_max* : Nombre maximum de vESXi supportés. Ce nombre correspond au nombre d'IP configurées dans le serveur DHCP.
  * *vsan* : Ajouter et configurer des clusters vSan dans chaque nouveau datacenter
  * *always_datastore* : Créer un datastore à partir du disque le plus petit **si le vESXi n'en possède pas**.
  Si vSan est activé, deux datastores pourront être présents sur chaque vESXi.
  * *ovf* : l'OVF/OVA à déployer pour la création des vESXi
  * *ovf_pwd* : le mot de passe pour se connecter au vESXi installé sur l'OVF. Ce mot de passe sera remplacé par le mot de passe de la section *virtual_esx*.
  * *iso_prefix* : Répertoire contenant les images ISO à copier sur le datastore des vESXi.
  **ATTENTION** il n'est pas possible de copier une image ISO sur un datastore de type vSan. **Le chemin DOIT finir par un /"**.
  * *iso*: Le nom des images ISO à copier sur le datastore des vESXi. Les noms doivent finir par *.iso*.

### Création des OVF
#### Création de l'OVF des ESXi virtuels (vESX)
* Créer une nouvelle machine virtuelle
  * Guest OS Family: Linux, Guest OS Version: Other Linux 64 bit
  * Customize hardware
    * CPU: Number: 2, tick both "Expose hardware assisted virtualization to the guest OS"
    and "Enable virtualized CPU performance counters"
    * Memory: 4 GB (pour l'utilisation NSX, les ESXi doivent avoir au minimum 8 GB de mémoire)
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
* Activer le *SSH client* à partir de l'interface web de l'ESXi
  * Networking > Firewall Rules > SSH client > Enable
* Création de l'OVF à partir d'un shell PowerShell (la connexion au vCenter doit être exécutée au préalable *vcenter-connect.ps1*)
  * `Get-VM -Name "vesx1" | Export-VApp -Destination vesx-ovf -Force`

#### Création de l'OVF d'une distribution tinyCore à partir de l'ISO *tinycore.iso*
* Installation de tinyCore sur le disque dur
  * Créer une VM avec 256 MB de mémoire, 200 MB de disque. Le disque doit être un **disque IDE**.
  * Démarrer la VM et booter sur l'ISO
  * `tce-load -wi tc-install`
  * `sudo tc-install.sh` : c - cd-rom, f - Frugal, 1 - Whole disk
  * Éteindre la VM et retirer l'ISO
* Installation du serveur SSH
  * Créer un mot de passe pour l'utilisateur 'tc' : `passwd`
  * Mot de passe : tiny00PWD
  ```
  tce-install -wi openssh
  cd /usr/local/etc/ssh/
  sudo cp sshd_config.orig sshd_config
  sudo /usr/local/etc/init.d/openssh start
  ```
  * lancement du service au démarrage `vim /opt/bootlocal.sh`
```
#!/bin/sh
# put other system startup commands here
/usr/local/etc/init.d/openssh start
```
  * Sauvegarder les modifications : `filetool.sh -b`
* Installation des VMware Tools
  * `tce-load -wi open-vm-tools-desktop`
  * Ajouter la ligne `/usr/local/etc/init.d/open-vm-tools start` au fichier `/opt/bootlocal.sh`
  * `filetool.sh -b`
* Sauvegarder les modifications sur le disque
  * `vim /opt/.filetool.lst`
```
opt
home
/etc/shadow
/usr/local/etc/ssh
```
  * `sudo vim /opt/bootlocal.sh`
```
/usr/local/etc/init.d/openssh start
```
  * `filetool.sh -b`
* Installation de l'outil de stress
  * Copier le fichier `stress.tcz` dans la VM via scp par exemple
  * Déplacer le fichier vers le répertoire `/mnt/sda1/tce/optional/`
  * Ajouter la ligne `stress.tcz` dans le fichier `/mnt/sda1/tce/onboot.lst`
  * `filetool.sh -b`

### Arrêt automatique du cluster
* Configuration des accès SSH des ESXi
  * Activer l'accès SSH via l'interface physique de management
    * F2 > Troubleshooting Options > Enable SSH
  * **ATTENTION** : l'activation SSH via l'interface web n'est pas permanente et sera perdue après le redémarrage
* Copier la clé SSH du poste d'installation sur les ESXi dans le bon fichier
  * `cat ~/.ssh/id_rsa.pub | ssh root@192.x.x.x 'cat >> /etc/ssh/keys-root/authorized_keys'`
* Utiliser le script *stop.sh* pour éteindre le cluster
* Ne pas oublier d'éteindre le switch ;)

### Mise en place du vSan via l'interface graphique du vCenter
* Les 3 vESXi sont déjà dans un datacenter
* Créer un cluster dans le datacenter (Ne pas activer vSan !)
* Déplacer les vESXi dans le cluster
* Activer le vSan sur les vESXi
  * Configure > Networking / VMKernel Adapters > Edit > Cocher vSan
* Activer le vSan du cluter
  * Configure > vSan / Services > Enable vSan
  * Laisser les valeurs par défaut (normalement, les disques durs des vESXi sont détectés)

### Tolérance aux pannes (Fault Tolerance)
* Pour activer la tolérance aux pannes sur une VM, il faut la configuration suivante :
  * Un cluster vSan avec la vSphere HA activée
  * Activer les options suivantes dans le VMkernel des ESXi : vMotion, Fault Tolerance Logging, vSan
  * Créer une VM avec un disque utilisant le 'Thick Provisioning'

### Resources
* Clone vESXi: https://www.virtuallyghetto.com/2013/12/how-to-properly-clone-nested-esxi-vm.html
* Promiscuous mode: https://isc.sans.edu/forums/diary/Running+Snort+on+VMWare+ESXi/15899/
* vSan Configuration: https://www.vladan.fr/vmware-vsan-configuration/
* Install tinyCore: https://iotbytes.wordpress.com/install-microcore-tiny-linux-on-local-disk/
* Install SSH on tinyCore: https://iotbytes.wordpress.com/configure-ssh-server-on-microcore-tiny-linux/

### Troubleshooting
#### Size of the vSan storage is incorrect
* Description: After creating the vSan datastore without error, the size of the datastore is less than the expected
  size.
  * instead of 120 GB (3 hosts x 40  GB) the size is (1 host x 40 GB) or (2 hosts x 40) GB
  * the system complains about missing backup nodes or missing fault tolerant domains
  * Compare the local Nnode UUID of ESXi with `esxcli vsan cluster get`
  * UUID must be unique
* Check the UUID of the ESXi
  * From powerCLI:
  ```
  Get-VMHost | Select Name, @{N='HW BIOS Uuid';E={$_.Extensiondata.Hardware.SystemInfo.Uuid}}, @{N='ESXi System UUid';E={(Get-Esxcli -VMHost $_).system.uuid.get()}}
  ```
  * From ESXi cli: `esxcli vsan cluster get`
  * The UUID must be unique. Delete the line *system/uuid* of the file `/etc/vmware/esx.conf`
  * Reboot the ESXi
* Take a look at the script `change-uuid.sh` and the file `uuid-hosts.txt`

#### Enable SSH connections FROM ESXi
* From vSphere
  * Select the ESXi Host
  * Configure > System > Firewall
  * Edit
  * Tick SSH Client
* From the ESXi Web UI
  * Networking > Firewall Rules
  * Right click on SSH client > Enable

#### Recurrent errors with PowerShell
* PowerCLI error: Operation is not valid due to the current state of the object.
  * Quitter PowerShell et relancer PowerShell

#### Connect to vCenter administration console
* https://42.42.4.4:5480/login
* Use the root account to login

#### Connect to vCenter databases
* ssh to the vCenter with the root account
* `/opt/vmware/vpostgres/current/bin/psql -d VCDB -U postgres`

