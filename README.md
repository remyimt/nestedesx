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
  * `sudo apt install libgconf2-4`
* Monter l'image sur le poste d'installation (Windows, Linux ou Mac) [Ubuntu 64 bits] et lancer l'installeur
```
mkdir /tmp/vcsa
sudo mount -o loop VMware-VCSA-all-6.7.0-10244745.iso /tmp/vcsa
cd /tmp/vcsa/vcsa-cli-installer/lin64/
```
* **ATTENTION**: Dans le fichier *embedded_vCSA_on_ESXi.json* tous les  mots de passe sont en clair !
  * Modifier les mots de passe du le fichier *embedded_vCSA_on_ESXi.json* et les reporter dans le fichier *configuration.json*
  * `./vcsa-deploy install --accept-eula --no-ssl-certificate-verification ./Files/embedded_vCSA_on_ESXi.json`
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

### Description des fichiers
* *configuration.json* : fichier de configuration
* *delete-student-vms.ps1* : script PowerShell effaçant les VM n'étant pas des vESXi
* *deploy.ps1* : Script PowerShell déployant l'infrastructure virtualisée via le vCenter
* *set-permissions.ps1* : Script PowerShell configurant les droits des nouveaux utilisateurs pour l'exécution des TP
* *shutdown-vms.ps1* : Script PowerShell pour éteindre le cluster sauf le vCenter
* *start.sh* : Script bash pour démarrer le cluster une fois les NUC allumés
* *stop.sh* : Script bash pour éteindre la totalité du cluster (sauf le switch)
* *tp-drs.txt* : TP sur vSphere DRS
* *tp-ha.txt* : TP sur vSphere HA
* *tp-vcenter* : TP sur les bases du vCenter

### Configuration de l'infrastructure
#### Démarrage rapide
* Éditer le fichier de configuration `configuration.json`
* Lancer le shell PowerShell: `pwsh`
* Lancer le script de déploiement : `./deploy.ps1`
* Créer un nouvel utilisateur par centre de données commençant par *new_dc_basename*. Le nom des utilisateurs doivent être *user_basename* suivi du numéro de création. Par exemple : adminDC1, adminDC2, adminDC3, adminDC4, etc. Les valeurs *new_dc_basename* et *user_basename* sont dans le fichier de configuration.
* Lancer le script configurant les permissions des nouveaux utilisateurs : ./set-permissions.ps1

#### Le fichier de configuration
* **ATTENTION** Tous les comptes et mots de passe sont définis dans le fichier de configuration.
* Le fichier de configuration est un fichier JSON. L'ordre des sections n'a pas d'importance. Toutes les propriétés disponibles sont présentees dans le `configuration.json` fourni comme exemple.
##### La section *switch* (optionnelle)
* Cette section est optionnelle car elle n'est pas utilisée par les scripts. Elle rassemble les informations d'administration et de connexion au switch pour faciliter le déroulement des exercices destinés aux étudiants.
##### La section *vcenter* (obligatoire)
* Cette section décrit les informations nécessaires à la gestion du vCenter (connexion, démarrage, arrêt).
  * *ip* : IP du vCenter
  * *host* : IP de l'ESXi hébergeant le vCenter
  * *user* : Utilisateur pour se connecter à vSphere
  * *pwd* : Mot de passe de l'utilisateur
##### La section *physical_esx* (obligatoire)
* Cette section décrit les informations nécessaires à la gestion des ESXi ainsi que le nombre de vESXi (ESXi installés dans des VM) hébergés par chaque ESXi (physique).
  * *ip* : IP de l'ESXi
  * *user* : Utilisateur pour se connecter à l'ESXi
  * *pwd* : Mot de passe de l'utilisateur
  * *nb_vesx* : Nombre de vESXi hébergés par l'ESXi
##### La section *virtual_esx* (obligatoire)
* Cette section décrit les informations utilisées pour la création des VM utilisées pour installer les ESXi virtuels (vESXi). 
  * *user* : Utilisateur pour se connecter au vESXi
  * *pwd* : Mot de passe de l'utilisateur
  * *basename* : Base de nom utilisé pour créer les VM contenant les vESXi. Le nom complet est formé par cette base suivie d'un chiffre.
  * *ip_base* : Trois premiers nombres de l'adresse IP des VM des vESXi
  * *ip_offset* : Début du dernier nombre de l'adresse IP des VM des vESXi. Ce nombre est incrémenté de 1 à chaque création de VM.
* Exemple de calcul d'IP
  * *ip_base* : *42.42.1.*
  * *ip_offset* : *40*
  * La 1ère VM créée (premier vESXi) aura pour IP *42.42.1.41*, la 2e VM aura pour IP *42.42.1.42*, la 13e aura pour IP *42.42.1.53*
##### La section *architecture* (obligatoire)
* Cette section regroupe toutes les informations supplémentaires nécessaires à la création de l'infrastructure virtuelle.
  * *main_dc* : Nom du datacenter contenant les ESXi physiques (ceux décrit dans la section *physical_esx*
  * *new_dc_basename* : Début du nom des centres de données contenant les vESXi utilisés pour les exercices décrit dans les fichiers *tp-vcenter.txt* et *tp-ha-drs.txt*. À ce nom est concaténé le numéro de création du datacenter. Ce numéro est incrémenté à chaque création d'un datacenter.
  * *user_basename* : Base de nom utilisé pour créer les utilisateurs supplémentaires avec des droits restreints sur l'architecture.
  * *nb_vesx_datacenter* : Nombre de datacenter contenant des vESXi
  * *vsan* : Ajouter et configurer des clusters vSan dans chaque nouveau datacenter
  * *always_datastore* : Créer un datastore à partir du disque le plus petit **si le vESXi n'en possède pas**. Si vSan est activé, deux datastore seront présents sur chaque vESXi.
  * *ovf* : l'OVF à déployer pour la création des vESXi
  * *iso_prefix* : Répertoire contenant les images ISO à copier sur le datastore des vESXi. **ATTENTION** il n'est pas possible de copier une image ISO sur un datastore de type vSan. **Le chemin DOIT finir par un /"**
  * *iso*: Le nom des images ISO à copier sur le datastore des vESXi. Les noms doivent finir par *.iso*.

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

### Création d'une VM avec un système tinyCore à partir de l'ISO tinyCore.iso
* Installation de tinyCore sur le disque dur
  * Démarrer la VM et booter sur l'ISO
  * `tce-load -wi tc-install`
  * `sudo tc-install.sh`
  * Éteindre la VM et retirer l'ISO
* Installation du serveur SSH
  * Créer un mot de passe pour l'utilisateur 'tc' : `passwd`
  * Mot de passe : tiny00PWD
  * `tce-install -wi openssh`
  * `cd /usr/local/etc/ssh/`
  * `sudo cp sshd_config.orig sshd_config`
  * `sudo /usr/local/etc/init.d/openssh start`
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
* PowerCLI error: Operation is not valid due to the current state of the object.
  * Quit PowerShell and restart it
