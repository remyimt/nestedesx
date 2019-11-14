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

### Configuration du switch Cisco
* Modèle : RV134W, doc : RV132W_RV134W.pdf
* Le poste d'installation est relié en ethernet sur le switch.
* La connexion Internet est configurée sur l'entrée WAN du switch.
* Adresses IP statiques pour les NUC
  * IP statiques : 192.168.1.[10-99]
  * Pinst 192.168.1.10 ac:87:a3:23:01:b2 (Poste d'installation)
  * Nuc1  192.168.1.11 b8:ae:ed:7c:3a:87
  * Nuc2  192.168.1.12 f4:4d:30:6a:8c:68
  * Nuc3  192.168.1.13 b8:ae:ed:7d:9e:80
  * Nuc4  192.168.1.14 f4:4d:30:69:68:2c
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
* Choisir l'ESXi qui hébergera le vCenter et noter son adresse IP
* Télécharger l'ISO du vCenter Service Appliance [VMware-VCSA-all-6.7.0-10244745.iso]
* Monter l'image sur le poste d'installation (Windows, Linux ou Mac) [Ubuntu 64 bits] et lancer l'installeur
   * mkdir /tmp/vcsa
   * sudo mount -o loop VMware-VCSA-all-6.7.0-10244745.iso /tmp/vcsa
   * cd /tmp/vcsa/vcsa-cli-installer/lin64/
* **ATTENTION**: Dans le fichier *embedded_vCSA_on_ESXi.json* tous les  mots de passe sont en clair !
  * Modifier les mots de passe du le fichier *embedded_vCSA_on_ESXi.json* et les reporter dans le fichier *configuration.json*
  * ./vcsa-deploy install --accept-eula --no-ssl-certificate-verification ./Files/embedded_vCSA_on_ESXi.json

### Installation de PowerCLI sur le poste d'installation
* PowerShell
'''
curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
curl https://packages.microsoft.com/config/ubuntu/16.04/prod.list | sudo tee /etc/apt/sources.list.d/microsoft.list
sudo apt-get update
sudo apt-get install -y powershell
'''
* PowerCLI
'''
Install-Module -Name VMware.PowerCLI -Scope CurrentUser
Update-Module -Name VMware.PowerCLI
'''

### Configuration de l'infrastructure
* Start the powerShell shell : pwsh
* Run the deployment script : ./deploy.ps1

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
  * cat ~/.ssh/id_rsa.pub | ssh root@IPvESXi 'cat >> /etc/ssh/keys-root/authorized_keys'
* Suppression des UUID du vESXi
  * Se connecter via SSH sur le vESXi et entrer les commandes suivantes
```text
esxcli system settings advanced set -o /Net/FollowHardwareMac -i 1
sed -i 's#/system/uuid.*##' /etc/vmware/esx.conf
/sbin/auto-backup.sh
poweroff
```
* Création de l'OVF à partir d'un shell PowerShell (la connexion au vCenter doit être exécutée au préalable *vcenter-connect.ps1*)
  * Get-VM -Name "vesx1" | Export-VApp -Destination vesx-ovf -Force

### Arrêt automatique du cluster
* Configuration des accès SSH des ESXi
  * Activer l'accès SSH via l'interface physique de management
    * F2 > Troubleshooting Options > Enable SSH
  * **ATTENTION** : l'activation SSH via l'interface web n'est pas permanente et sera perdue après le redémarrage
* Copier la clé SSH du poste d'installation sur les ESXi dans le bon fichier
  * cat ~/.ssh/id_rsa.pub | ssh root@192.x.x.x 'cat >> /etc/ssh/keys-root/authorized_keys'
* Utiliser le script 'shutdown.sh' pour éteindre le cluster
  * Extinction de toutes les VM
  * Extinction des ESXi physiques
  * Ne pas oublier d'éteindre le switch ;)

### Resources
* https://www.virtuallyghetto.com/2013/12/how-to-properly-clone-nested-esxi-vm.html

